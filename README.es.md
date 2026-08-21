# Lefant Home Assistant LocalTuya

🌐 [English](README.md) | [Español](README.es.md)

[![Platform](https://img.shields.io/badge/platform-Windows-0078D4)](https://www.microsoft.com/windows) [![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB)](https://www.python.org/)

> Extrae el Device ID y la Local Key de Lefant para integrarlo con Home Assistant mediante LocalTuya.

> Esta es la traducción al español del README principal. En caso de discrepancia, la versión en inglés es la referencia.

Esta herramienta comunitaria ayuda a propietarios de determinados robots Lefant a obtener los datos de conexión local necesarios para Home Assistant manteniendo el robot vinculado a la aplicación oficial de Lefant. No distribuye, sustituye ni modifica el APK de Lefant.

## Índice

- [Inicio rápido](#inicio-rápido)
- [Qué hace este proyecto](#qué-hace-este-proyecto)
- [Configuración validada](#configuración-validada)
- [Arquitectura](#arquitectura)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Instalar la aplicación Lefant](#instalar-la-aplicación-lefant)
- [Frida Server](#frida-server)
- [Uso](#uso)
- [devices.json](#devicesjson)
- [Home Assistant y LocalTuya](#home-assistant-y-localtuya)
- [Templates de LocalTuya listos para usar](#templates-de-localtuya-listos-para-usar)
- [Lefant M210 Pro Omni](#lefant-m210-pro-omni)
- [Contribuir con un template para otro modelo Lefant](#contribuir-con-un-template-para-otro-modelo-lefant)
- [Solución de problemas](#solución-de-problemas)
- [Seguridad y privacidad](#seguridad-y-privacidad)
- [Aviso legal](#aviso-legal)

## Inicio rápido

1. Instala Python, Node.js/npm, Android Studio/ADB y Frida.
2. Crea o utiliza un emulador Android compatible con el flujo `adb root` que necesita el launcher.
3. Instala la aplicación oficial de Lefant: preferiblemente desde Google Play si está disponible en ese emulador, o de forma opcional mediante archivos APK locales aportados por ti.
4. Descarga y coloca localmente un binario `frida-server` compatible.
5. Ejecuta:

   ```powershell
   .\lefant_launcher.ps1
   ```

6. Inicia sesión manualmente en Lefant si es necesario y carga la lista de dispositivos.
7. Pulsa ENTER cuando el launcher lo solicite.
8. Utiliza el Device ID y la Local Key extraídos en LocalTuya.

Los archivos APK son opcionales; consulta [Instalar la aplicación Lefant](#instalar-la-aplicación-lefant) para ver las rutas locales compatibles.

## Qué hace este proyecto

Algunos robots Lefant están basados en componentes Tuya/ThingClips. Para configurar un dispositivo de forma local, Home Assistant LocalTuya normalmente necesita su Device ID, Local Key, dirección IP de la red local y versión del protocolo Tuya.

Después de vincular un robot desde la aplicación Lefant, su Local Key puede no estar disponible desde un proyecto normal de Tuya IoT Cloud. Este proyecto lee los objetos `DeviceBean` que ya ha cargado la aplicación oficial de Lefant autenticada dentro de un entorno Android controlado por el propietario. Exporta el Device ID y la Local Key sin sacar el robot de la aplicación Lefant.

Esto no implica compatibilidad con todos los modelos Lefant. La versión del protocolo y los datapoints dependen de cada dispositivo. El extractor exporta deliberadamente únicamente los valores que realmente lee y no presupone ninguna versión de protocolo.

## Configuración validada

Se ha validado la siguiente configuración:

- Lefant M210 Pro Omni
- Aplicación Lefant `3.3.25`
- Protocolo Tuya `3.5` para ese modelo
- Windows como sistema anfitrión
- Emulador Android compatible con `adb root`

## Arquitectura

```text
PC con Windows
  └─ lefant_launcher.ps1
       └─ Emulador Android
            └─ Aplicación oficial Lefant (inicio de sesión manual)
                 └─ frida-server
                      └─ Extracción de DeviceBean
                           └─ devices.json
                                └─ LocalTuya
                                     └─ Home Assistant
```

- El launcher de PowerShell inicia o reutiliza un emulador Android y prepara Frida.
- La aplicación oficial Lefant es donde el propietario inicia sesión y carga su propia lista de dispositivos.
- `frida-server` permite que el cliente Frida de Windows se conecte al emulador controlado por el usuario.
- El agente TypeScript enumera las instancias `DeviceBean` cargadas.
- El exportador Python elimina duplicados por Device ID y escribe `devices.json`.
- LocalTuya utiliza esos valores junto con la dirección IP del robot y la versión de protocolo correspondiente.

## Requisitos

- [Python 3.10+](https://www.python.org/downloads/)
- [Node.js y npm](https://nodejs.org/)
- [Android Studio](https://developer.android.com/studio), incluido un AVD de Android Emulator
- [Android SDK Platform Tools / ADB](https://developer.android.com/tools/releases/platform-tools)
- [Frida](https://frida.re/) y una versión compatible de [`frida-server`](https://github.com/frida/frida/releases)
- [HACS](https://www.hacs.xyz/) para Home Assistant
- [xZetsubou/hass-localtuya](https://github.com/xZetsubou/hass-localtuya), el fork de LocalTuya para el que está pensado este proyecto

El código actual de xZetsubou LocalTuya incluye el protocolo `3.5` entre las versiones soportadas. Este repositorio está pensado para ese fork, no para el antiguo repositorio upstream `rospogrigio/localtuya`. Es responsabilidad del usuario seleccionar el protocolo que corresponda a su dispositivo.

El emulador debe ser compatible con `adb root`, ya que el launcher coloca e inicia `frida-server` en `/data/local/tmp/frida-server`. Las imágenes Google APIs suelen ser más adecuadas que las imágenes Google Play para este uso porque aquí es importante disponer de `adb root`.

## Instalación

1. Clona el repositorio:

   ```powershell
   git clone https://github.com/hectorzin/Lefant-Home-Assistant-LocalTuya.git
   cd Lefant-Home-Assistant-LocalTuya
   ```

2. Instala las dependencias de Python:

   ```powershell
   py -m pip install -r requirements.txt
   ```

3. Instala las dependencias de Node:

   ```powershell
   npm install
   ```

   El exportador Python también puede ejecutar `npm install` automáticamente si falta `frida-java-bridge`, aunque se recomienda instalar las dependencias previamente.

4. Crea o elige un AVD de Android Emulator compatible con `adb root`. El nombre de AVD predeterminado utilizado por el launcher es `Pixel_6`.

5. Descarga un `frida-server` que coincida tanto con la versión del cliente Frida instalada como con la ABI del emulador. No lo añadas a Git.

## Instalar la aplicación Lefant

Aportar archivos APK es **opcional**. Si el emulador dispone de Google Play, la forma más sencilla es instalar directamente desde ahí la aplicación oficial de Lefant, abrirla e iniciar sesión normalmente.

Si Google Play no está disponible o prefieres una instalación local, el launcher admite archivos APK proporcionados por el usuario. La aplicación Lefant y los archivos APK no están incluidos en este repositorio. Tener Google Play disponible no es suficiente por sí solo: el emulador debe seguir siendo compatible con el flujo `adb root` que necesita el launcher.

El launcher comprueba estas ubicaciones para el APK base:

```text
./lefant.apk
./apk/lefant.apk
```

Si la aplicación utiliza APKs divididos, coloca los splits junto al APK base:

```text
apk/
  lefant.apk
  split_config.arm64_v8a.apk
  split_config.es.apk
  split_config.xxhdpi.apk
```

El launcher detecta los archivos `split_config*.apk` y utiliza `adb install-multiple`. Estos archivos son opcionales, están ignorados por Git y debe aportarlos el usuario. Este repositorio no distribuye APKs ni enlaza a sitios no oficiales para descargarlos.

## Frida Server

La versión del cliente Frida y la de `frida-server` deben coincidir. El launcher detecta la versión instalada del cliente Frida y la ABI del emulador y, a continuación, busca un binario de servidor compatible.

Ubicaciones locales compatibles:

```text
./frida-server
./frida/frida-server
./frida/frida-server-VERSION-android-x86_64
```

Utiliza `-FridaServerPath` para indicar una ruta explícita:

```powershell
.\lefant_launcher.ps1 `
  -FridaServerPath .\frida\frida-server-17.17.0-android-x86_64
```

El launcher copia un binario compatible a `/data/local/tmp/frida-server`, configura sus permisos, lo inicia mediante `adb root` y verifica su funcionamiento desde Windows. No añadas el binario al repositorio.

## Uso

Inicia el flujo normal:

```powershell
.\lefant_launcher.ps1
```

El launcher realiza automáticamente lo siguiente:

1. Localiza ADB.
2. Reutiliza un emulador Android en ejecución cuando es posible o inicia el AVD configurado.
3. Espera a que Android termine de arrancar.
4. Comprueba si Lefant está instalada y, opcionalmente, instala un APK aportado por el usuario.
5. Abre la aplicación oficial Lefant.
6. Permite iniciar sesión manualmente si es necesario y esperar a que se cargue la lista de dispositivos.
7. Prepara y verifica `frida-server`.
8. Conecta Frida a Lefant, extrae los datos de `DeviceBean` y escribe `devices.json`.

La Local Key aparece enmascarada por defecto en la salida del terminal. Para mostrarla completa:

```powershell
.\lefant_launcher.ps1 -ShowKey
```

`devices.json` siempre contiene la Local Key completa, así que debe tratarse como información sensible.

### Parámetros útiles del launcher

| Parámetro | Función | Ejemplo |
| --- | --- | --- |
| `-Serial` | Reutilizar un emulador ADB concreto | `-Serial emulator-5554` |
| `-Adb` | Utilizar un ejecutable ADB específico | `-Adb C:\Android\Sdk\platform-tools\adb.exe` |
| `-Avd` | AVD que se iniciará si no hay ningún emulador conectado | `-Avd Pixel_6` |
| `-EmulatorPath` | Ruta explícita al ejecutable de Android Emulator | `-EmulatorPath C:\Android\Sdk\emulator\emulator.exe` |
| `-FridaServerPath` | Binario `frida-server` compatible indicado explícitamente | `-FridaServerPath .\frida\frida-server-17.17.0-android-x86_64` |
| `-FridaAddress` | Endpoint remoto autorizado de Frida | `-FridaAddress 127.0.0.1:27042` |
| `-Output` | Archivo JSON de salida | `-Output .\devices.json` |
| `-ShowKey` | Mostrar la Local Key completa en el terminal | `-ShowKey` |

## devices.json

Ejemplo con valores ficticios seguros:

```json
[
  {
    "name": "Robot Vacuum",
    "device_id": "xxxxxxxxxxxxxxxxxxxxxx",
    "local_key": "xxxxxxxxxxxxxxxx",
    "mac": "e82f126407d4",
    "ip": "192.168.1.123"
  }
]
```

- El Device ID procede del `DeviceBean` de Lefant/ThingClips.
- La Local Key es material sensible utilizado para la autenticación local.
- La dirección MAC se extrae del `DeviceBean` cuando ese valor está disponible. Se escribe tal cual la devuelve el getter y puede quedar vacía en algunos modelos.
- La IP se extrae de `DeviceBean.getIp()` cuando ese valor está disponible. Se escribe tal cual la devuelve el getter y puede quedar vacía o desactualizada; no se asume que sea una dirección LAN fiable. Si falta o está desfasada, la IP puede obtenerse desde las concesiones DHCP del router, el descubrimiento de LocalTuya o TinyTuya.
- `devices.json` está ignorado por Git.
- No publiques Local Keys ni Device IDs privados innecesariamente.

## Home Assistant y LocalTuya

Instala [xZetsubou/hass-localtuya](https://github.com/xZetsubou/hass-localtuya) mediante HACS:

1. Abre **HACS** → **Integrations**.
2. Abre el menú → **Custom repositories**.
3. Añade `https://github.com/xZetsubou/hass-localtuya`.
4. Selecciona la categoría **Integration**.
5. Instala **LocalTuya** y reinicia Home Assistant si te lo solicita.
6. Abre **Settings** → **Devices & services** → **Add integration** → **LocalTuya**.

Introduce los valores correspondientes a tu robot:

- Host / dirección IP
- Device ID
- Local Key
- Versión del protocolo

Puedes encontrar la dirección IP mediante las concesiones DHCP del router, el descubrimiento de LocalTuya o, de forma opcional, [TinyTuya](https://github.com/jasonacox/tinytuya). TinyTuya no es obligatorio.

## Templates de LocalTuya listos para usar

Este repositorio incluye templates reutilizables de LocalTuya para estos modelos Lefant:

- `Lefant_A1_Pro.yaml`
- `Lefant_M210_Pro_Omni.yaml`

Más abajo encontrarás documentación detallada para el M210 Pro Omni. Los demás templates incluidos pueden utilizarse directamente aunque todavía no dispongan de su propia sección específica.

Copia el archivo correspondiente desde el directorio `templates/` de este repositorio al directorio de templates de LocalTuya dentro de la configuración de Home Assistant:

```text
/config/custom_components/localtuya/templates/
```

Si trabajas con rutas relativas al directorio de configuración de Home Assistant, la misma ubicación es:

```text
custom_components/localtuya/templates/
```

A continuación, añade el dispositivo en LocalTuya. Durante el flujo **Add new device**, selecciona **Use saved template**; LocalTuya mostrará en ese paso los templates almacenados en ese directorio. Reinicia Home Assistant después de copiar un template si no aparece en la lista.

Los templates son específicos de cada modelo. Comprueba los DPs disponibles antes de aplicar uno a un modelo diferente y selecciona la versión de protocolo que corresponda al dispositivo: las versiones del protocolo Tuya no son universales entre los distintos modelos Lefant.

## Lefant M210 Pro Omni

La siguiente configuración está validada para el Lefant M210 Pro Omni utilizando el protocolo Tuya `3.5`. Es específica de este modelo y no debe considerarse un mapeo universal para Lefant.

Configura la entidad vacuum con:

- Power DP: `1`
- Pause DP: `2`
- Mode DP: `4`
- Status DP: `5`
- Fan speed DP: `9`
- Clean time DP: `16`
- Clean area DP: `17`
- Locate DP: `27`

Los valores de modo validados son `smart`, `chargego`, `zone` y `pose`. Los valores de velocidad del ventilador validados son `gentle`, `normal` y `strong`.

Utiliza estos grupos de estado para la entidad vacuum:

| Estado | Valores |
| --- | --- |
| Idle | `standby`, `sleep`, `charge_done` |
| Docked | `charging`, `charge_done`, `sleep` |
| Returning | `goto_charge` |
| Paused | `paused` |

| DP | Nombre conocido | Uso sugerido en LocalTuya |
| --- | --- | --- |
| 1 | `power_go` | Encendido/limpieza del vacuum |
| 2 | `pause` | Pausa del vacuum |
| 3 | `switch_charge` | Botón independiente **Volver a la base**; establecer `true` |
| 4 | `mode` | Modo del vacuum |
| 5 | `status` | Estado del vacuum de solo lectura; puede informar `goto_charge` |
| 9 | `suction` | Velocidad de aspiración |
| 10 | `water_output` | DP conocido; su comportamiento no se documenta aquí |
| 14 | `auto_boost` | Switch independiente |
| 15 | `break_clean` | Entidad independiente; el template incluido lo utiliza como switch. Valida su comportamiento antes de representarlo como diagnóstico o sensor binario |
| 16 | `clean_time` | Sensor: tiempo de limpieza |
| 17 | `clean_area` | Sensor: área limpiada |
| 23 | `battery_percentage` | Sensor independiente de batería (`%`) |
| 27 | `seek` | Localizar el vacuum |

Para este modelo, utiliza DP 3 (`switch_charge = true`) para la acción normal **Volver a la base** de Home Assistant. No sustituyas esta acción por `mode=chargego`. DP 5 es un estado de solo lectura y puede informar `goto_charge` mientras el robot vuelve a su base.

## Contribuir con un template para otro modelo Lefant

Si otro modelo Lefant funciona con LocalTuya, puedes exportar o preparar su configuración, eliminar la información sensible, añadir un template dentro de `templates/` y abrir un Pull Request.

Incluye el modelo Lefant exacto, la versión del protocolo Tuya probada, la versión de la aplicación Lefant utilizada (si se conoce), el mapeo de DPs, la confirmación de que funcionan los controles básicos y cualquier particularidad específica del modelo.

No incluyas una `local_key`, un `device_id` real, una dirección IP privada, datos de cuenta ni ninguna otra información personal en un template, ejemplo, issue o Pull Request.

## Solución de problemas

| Problema | Qué comprobar |
| --- | --- |
| No se encuentra ADB | Instala Platform Tools, añádelo al `PATH` o utiliza `-Adb`. |
| No se detecta ningún emulador | Comprueba el nombre del AVD, utiliza `-Avd` y espera hasta que `adb devices` muestre `device`. |
| `adb root` no está soportado | Utiliza un emulador/imagen del sistema que permita `adb root`; de lo contrario el launcher no puede desplegar el servidor. |
| Lefant no está instalada | Instálala desde Google Play si está disponible en el emulador, instálala manualmente o utiliza los APKs locales opcionales en una ubicación compatible. |
| Falla la instalación de splits | Mantén juntos el APK base y todos los archivos `split_config*.apk` disponibles. |
| Las versiones del cliente y servidor Frida no coinciden | Descarga el servidor correspondiente a la versión del cliente Frida y a la ABI del emulador. |
| `frida-server` no se está ejecutando | Comprueba `adb root`, la ruta del binario, la ABI y la versión. |
| No se puede conectar Frida a Lefant | Abre la aplicación oficial, comprueba que esté ejecutándose y que la verificación de Frida haya finalizado correctamente. |
| No se encuentra ningún `DeviceBean` | Carga completamente la lista de dispositivos de Lefant y vuelve a intentarlo. |
| Hay varios dispositivos ADB | Utiliza `-Serial emulator-XXXX`. |
| No aparece `devices.json` | La extracción no encontró un DeviceBean completo; revisa la lista de dispositivos y los errores anteriores. |
| Advertencia sobre la versión de Lefant | La versión validada de la aplicación es `3.3.25`; otras versiones pueden funcionar, pero no están validadas. |

## Seguridad y privacidad

- Las Local Keys autentican la comunicación local con el dispositivo. Mantenlas privadas.
- No publiques `devices.json` ni añadas Local Keys a Git.
- Evita publicar Device IDs privados si no es necesario.
- Este proyecto solo actúa sobre un entorno Android controlado por el usuario.
- El usuario inicia sesión manualmente en Lefant; el proyecto no recopila ni transmite credenciales.

## Aviso legal

Este es un proyecto comunitario no oficial. No está afiliado con Lefant, Tuya, ThingClips ni Home Assistant. Lefant, Tuya, ThingClips y Home Assistant son marcas comerciales de sus respectivos propietarios.

El proyecto está destinado a facilitar la interoperabilidad con dispositivos propiedad del usuario. No se distribuyen APKs de Lefant, binarios de `frida-server` ni otros binarios propietarios.
