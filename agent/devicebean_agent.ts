import Java from "frida-java-bridge";

const seen = new Set<string>();

function safeCall(obj: any, method: string): string {
  try {
    const fn = obj[method];
    if (!fn) {
      return "";
    }
    return String(fn.call(obj) || "");
  } catch (_) {
    return "";
  }
}

function rememberMac(byId: Map<string, string>, deviceId: string, mac: string): void {
  if (deviceId && mac && !byId.has(deviceId)) {
    byId.set(deviceId, mac);
  }
}

function macFromDevRespBean(deviceId: string): string {
  try {
    const ThingHomeSdk = Java.use("com.thingclips.smart.home.sdk.ThingHomeSdk");
    const data = ThingHomeSdk.getDataInstance();
    if (!data) {
      return "";
    }
    const resp = data.getDevRespBean(deviceId);
    if (!resp) {
      return "";
    }
    return safeCall(resp, "getMac");
  } catch (_) {
    return "";
  }
}

function macFromTuyaHandle(deviceId: string): string {
  try {
    const Utils = Java.use("com.yunshi.robotlife.uitils.TuyaDeviceHandleUtils");
    const handle = Utils.getInstance();
    if (!handle) {
      return "";
    }
    const currentId = safeCall(handle, "getDevId") || safeCall(handle, "getmThridDevId");
    if (!currentId || currentId !== deviceId) {
      return "";
    }
    const fromHandle = safeCall(handle, "getLaserDeviceMac");
    if (fromHandle) {
      return fromHandle;
    }
    try {
      return safeCall(handle.getDevice(), "getDeviceMac");
    } catch (_) {
      return "";
    }
  } catch (_) {
    return "";
  }
}

function chooseMacs(className: string, idMethod: string, macMethod: string, byId: Map<string, string>, done: () => void): void {
  try {
    Java.choose(className, {
      onMatch(obj: any) {
        rememberMac(byId, safeCall(obj, idMethod), safeCall(obj, macMethod));
      },
      onComplete: done,
    });
  } catch (_) {
    done();
  }
}

function collectSweeperMacs(byId: Map<string, string>, done: () => void): void {
  try {
    Java.choose("com.yunshi.robotlife.device.SweeperDevice", {
      onMatch(obj: any) {
        const deviceId = safeCall(obj, "getDeviceId") || safeCall(obj, "getDevId");
        rememberMac(byId, deviceId, safeCall(obj, "getDeviceMac"));
      },
      onComplete: done,
    });
  } catch (_) {
    done();
  }
}

function fillFallbackMacs(records: Array<{ deviceId: string; mac: string }>, done: () => void): void {
  for (const record of records) {
    if (!record.mac) {
      record.mac = macFromDevRespBean(record.deviceId) || macFromTuyaHandle(record.deviceId);
    }
  }
  if (records.every((record) => Boolean(record.mac))) {
    done();
    return;
  }
  const byId = new Map<string, string>();
  collectSweeperMacs(byId, () => {
    chooseMacs("com.yunshi.robotlife.bean.HomeDeviceInfoBean", "getThird_dev_id", "getMac", byId, () => {
      for (const record of records) {
        if (!record.mac) {
          record.mac = byId.get(record.deviceId) || "";
        }
      }
      done();
    });
  });
}

if (!Java.available) {
  send({ type: "error", error: "Frida Java bridge no disponible: ART/Java no está disponible en este proceso." });
  send({ type: "complete" });
} else {
  Java.perform(() => {
    try {
      const records: Array<{ name: string; deviceId: string; localKey: string; mac: string }> = [];
      Java.choose("com.thingclips.smart.sdk.bean.DeviceBean", {
        onMatch(d: any) {
          try {
            const deviceId = String(d.getDevId() || "");
            const localKey = String(d.getLocalKey() || "");
            let name = "";
            let mac = "";
            try {
              name = String(d.getName() || "");
            } catch (_) {
              name = "";
            }
            try {
              mac = String(d.getMac() || "");
            } catch (_) {
              mac = "";
            }
            if (deviceId && localKey && !seen.has(deviceId)) {
              seen.add(deviceId);
              records.push({ name, deviceId, localKey, mac });
            }
          } catch (_) {
            // An invalid/partially finalized heap object is ignored.
          }
        },
        onComplete() {
          const emit = () => {
            for (const record of records) {
              send({
                type: "device",
                name: record.name,
                device_id: record.deviceId,
                local_key: record.localKey,
                mac: record.mac,
              });
            }
            send({ type: "complete" });
          };
          try {
            fillFallbackMacs(records, emit);
          } catch (_) {
            emit();
          }
        },
      });
    } catch (error) {
      send({ type: "error", error: `Frida Java bridge no disponible: ${String(error)}` });
    }
  });
}
