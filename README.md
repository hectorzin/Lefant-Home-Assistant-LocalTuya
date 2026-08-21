# Lefant DeviceBean Exporter

Utilidad de interoperabilidad local para dispositivos Lefant propios y Home Assistant. El flujo final es:

```text
Lefant oficial → lefant_launcher.ps1 → Frida/frida-server →
lefant_devicebean_export.py → agent/devicebean_agent.ts → devices.json
```

El usuario inicia sesión normalmente en la app oficial Lefant con su propia cuenta. La herramienta solo enumera objetos `DeviceBean` ya cargados en esa sesión autenticada y exporta `name`, `device_id` y `local_key` de sus dispositivos.

No modifica la APK, no contiene credenciales Lefant, no suplanta la identidad cloud, no inspecciona tráfico y no opera dispositivos. Usa únicamente teléfonos o emuladores que controles y dispositivos vinculados a tu cuenta. `local_key` es un secreto: no subas `devices.json` ni lo compartas.

## Requisitos

- Windows, Python 3.10+ y Node.js/npm.
- Android Platform Tools (`adb`) y Android Emulator.
- Un AVD con `adb root` habilitado; el valor predeterminado es `Pixel_6`.
- Paquetes Python:

```powershell
py -m pip install -r requirements.txt
```

- Un binario `frida-server` compatible aportado por ti. El launcher detecta la versión del cliente y la ABI del emulador, pero no descarga binarios.

## Uso

```powershell
.\lefant_launcher.ps1
```

El launcher reutiliza un emulador ADB operativo o inicia `Pixel_6`, espera `sys.boot_completed=1`, instala Lefant solo si no está presente y abre la app oficial. Tras el login normal y la carga de dispositivos, prepara y verifica `frida-server`, y ejecuta el exportador.

Parámetros habituales:

```powershell
.\lefant_launcher.ps1 -Serial emulator-5554 `
  -Avd Pixel_6 `
  -EmulatorPath "C:\Android\Sdk\emulator\emulator.exe" `
  -EmulatorArgs "-no-snapshot", "-gpu", "swiftshader_indirect" `
  -FridaServerPath .\frida\frida-server-<version>-android-x86_64 `
  -Output .\devices.json
```

Para instalar Lefant de forma opcional, el launcher admite una APK local en `./lefant.apk` o `./apk/lefant.apk`. También reconoce instalaciones divididas por `split_config*.apk` en la misma carpeta. Las APK no forman parte del repositorio.

## Frida 17+

El agente TypeScript importa `frida-java-bridge` y el exportador lo bundlea mediante `frida.Compiler` antes de llamar a `create_script`. Si falta `node_modules/frida-java-bridge`, el exportador ejecuta `npm install --no-audit --no-fund` usando `package.json`. Si no puede preparar o compilar el bridge, informa `Frida Java bridge no disponible`.

## Salida

La salida se deduplica por `device_id` y contiene solo los valores extraídos:

```json
[
  {
    "name": "Lefant M210 PRO OMNI",
    "device_id": "...",
    "local_key": "..."
  }
]
```

La clave queda enmascarada en la consola. Usa `-ShowKey` en el launcher o `--show-key` al invocar directamente `lefant_devicebean_export.py` para verla de forma explícita.
