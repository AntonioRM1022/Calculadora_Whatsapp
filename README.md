# Calculadora For Status Whatsapp

Aplicacion movil desarrollada en Flutter para calcular de forma rapida y sencilla el precio de venta sugerido de calzado y compartir la oferta directamente en los estados de WhatsApp.

## Descripcion

Esta aplicacion esta disenada con una interfaz limpia, compacta y de alto contraste bajo Material Design 3, pensada para facilitar el flujo de trabajo paso a paso mediante tarjetas desplegables:

1. **Costo del zapato**: Campo numerico de gran tamano que limpia el valor anterior al tocarlo para permitir una captura inmediata.
2. **Ganancia extra (Opcional)**: Botones de seleccion rapida (`+$10`, `+$15`, `+$20`, `+$30`) con opcion de desmarcar o continuar sin monto adicional.
3. **Tipo de calzado**: Seleccion rapida de categoria entre `Dama`, `Caballero` y `Nino`.
4. **Foto del calzado**: Seleccion de imagen directamente desde la galeria del dispositivo con vista previa integrada.
5. **Precio Final**: Calculo automatico en tiempo real con el desglose de costo y ganancia total.
6. **Acciones rapidas**:
   - **Compartir en Estado**: Abre el selector nativo del sistema enviando la fotografia seleccionada junto con el texto de oferta generado automaticamente.
   - **Limpiar**: Reinicia todos los campos, contrae los pasos posteriores, abre el paso 1 y despliega el teclado numerico de forma automatica para ingresar un nuevo producto.

## Formula de Calculo

El precio final sugerido se calcula automaticamente aplicando un margen base del 50% sobre el costo mas la ganancia extra seleccionada:

```
Ganancia Base = Costo / 2
Ganancia Total = Ganancia Base + Ganancia Extra (opcional)
Precio Final = Costo + Ganancia Total
```

El mensaje generado al compartir sigue el formato:

```
Zapato de [Categoria] precio de oferta $[PrecioFinal]
```

## Tecnologias y Dependencias

- **Flutter** (Material Design 3)
- **Dart** (`>=3.2.0 <4.0.0`)
- [`image_picker`](https://pub.dev/packages/image_picker): Seleccion de imagenes desde la galeria del dispositivo.
- [`share_plus`](https://pub.dev/packages/share_plus): Integracion con el selector nativo para compartir archivos e imagenes (`Share.shareXFiles`).

## Estructura del Proyecto

```
lib/
  main.dart          # Punto de entrada, Splash Screen y pantalla principal interactiva
assets/
  app_icon.png       # Icono principal y recurso de pantalla de inicio
android/             # Configuracion nativa de Android, iconos launcher y splash screen
ios/                 # Configuracion nativa de iOS
pubspec.yaml         # Definicion de dependencias y recursos
```

## Requisitos Previos

- Flutter SDK instalado y configurado.
- Android SDK y JDK 17 para compilacion en dispositivos Android.

## Instalacion y Ejecucion

1. Clonar el repositorio:

```bash
git clone https://github.com/AntonioRM1022/Calculadora_Whatsapp.git
cd Calculadora_Whatsapp
```

2. Instalar las dependencias:

```bash
flutter pub get
```

3. Ejecutar en un dispositivo conectado:

```bash
flutter run
```

4. Generar el archivo APK de produccion:

```bash
flutter build apk --release
```

El archivo compilado se generara en la ruta `build/app/outputs/flutter-apk/app-release.apk`.
