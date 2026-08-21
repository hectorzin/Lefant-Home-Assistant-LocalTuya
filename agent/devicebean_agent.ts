import Java from "frida-java-bridge";

const seen = new Set<string>();

if (!Java.available) {
  send({ type: "error", error: "Frida Java bridge no disponible: ART/Java no está disponible en este proceso." });
  send({ type: "complete" });
} else {
  Java.perform(() => {
    try {
      Java.choose("com.thingclips.smart.sdk.bean.DeviceBean", {
        onMatch(d: any) {
          try {
            const deviceId = String(d.getDevId() || "");
            const localKey = String(d.getLocalKey() || "");
            const name = String(d.getName() || "");
            if (deviceId && localKey && !seen.has(deviceId)) {
              seen.add(deviceId);
              send({ type: "device", name, device_id: deviceId, local_key: localKey });
            }
          } catch (_) {
            // An invalid/partially finalized heap object is ignored.
          }
        },
        onComplete() {
          send({ type: "complete" });
        },
      });
    } catch (error) {
      send({ type: "error", error: `Frida Java bridge no disponible: ${String(error)}` });
    }
  });
}
