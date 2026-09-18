# Edición, notas y planificación

## Diagramas

- Selecciona varios elementos o trazos con el recuadro o lazo y pulsa **Agrupar**. Tocar un miembro selecciona todo el grupo. **Desagrupar** devuelve la selección independiente.
- Los grupos se guardan en el documento, se pueden mover, duplicar y deshacer. Las copias reciben identificadores de grupo nuevos.
- Selecciona un elemento y arrastra el control de la esquina inferior derecha para ampliarlo o reducirlo. El cambio es proporcional y se guarda; todo el gesto ocupa un paso de deshacer.
- Con el dedo, arrastrar sobre un elemento no seleccionado desplaza la vista. Toca y suelta para seleccionarlo; después puedes arrastrarlo. El modo mano siempre desplaza. Dos dedos siguen controlando desplazamiento y zoom.

## Bocetos en notas

**Insertar boceto** añade un recuadro de 640 × 320 a la nota. Tiene dibujo libre, borrador, bloques, texto, conexiones, tamaño y deshacer. El recuadro se muestra directamente debajo del texto de la nota; no crea un lienzo global.

**Copiar boceto** y **Pegar boceto** transfieren una copia independiente. Editar una copia no modifica la otra. El contenido está incluido en el JSON de la nota y sobrevive al cierre de la app.

La herramienta de IA `sketch_note` admite `embedded: true` para insertar un dibujo dentro de uno de estos recuadros. `embedded: false` conserva el dibujo sobre la página para anotaciones y subrayados.

## Proyectos y calendario

Los proyectos tienen pestañas **Actividades** y **Requerimientos**. Cada elemento tiene título, descripción y estado (por hacer, en curso, terminado), fecha opcional y elementos hijos mediante **Desglosar**. Los requerimientos también tienen criterios de aceptación.

Los elementos con fecha aparecen en el calendario. El selector permite filtrar por proyecto y abrir la actividad o requerimiento para editarlo. Desde un proyecto se puede abrir **Planificar con IA** o **Pensar requerimientos con IA**. El asistente consulta lo existente y registra o actualiza elementos usando identificadores del proyecto.

La base de datos pasa de versión 6 a 7 con una tabla nueva. No se reemplazan notas, tareas ni eventos existentes.

## IA

**Ajustes → Asistente** permite elegir Gemini, modelo local, DeepSeek o MiMo. En las secciones de DeepSeek y MiMo se configuran el modelo y la API key; las claves se guardan en el llavero del sistema y se pueden eliminar.

Los cuatro motores comparten las herramientas de planificación. El modelo local tiene protección contra turnos simultáneos, historial reciente acotado, renovación periódica de sesiones y cierre de sesiones al cambiar o recuperar una conversación. Los errores de parámetros vuelven al modelo para que pueda corregirlos.

El botón de voz utiliza dictado y voz del sistema con el motor elegido cuando se usa local, DeepSeek o MiMo. Gemini Live se reserva para Gemini fuera del modo económico. Esta implementación no convierte los otros motores en modelos de audio en tiempo real ni garantiza la misma calidad o latencia que Gemini Live.

Endpoints y modelos iniciales se verificaron con documentación oficial:

- [DeepSeek: modelos y API](https://api-docs.deepseek.com/quick_start/pricing/): `https://api.deepseek.com`, `deepseek-flash`.
- [MiMo: primera llamada y herramientas](https://mimo.mi.com/docs/zh-CN/quick-start/summary/first-api-call): `https://api.xiaomimimo.com/v1`, `mimo-v2.5-pro`.

## Tema

Los widgets que leen la paleta global ahora dependen del tema para reconstruirse cuando cambia. Los pintores también invalidan su dibujo al cambiar la paleta. Se corrigieron pares de texto/fondo en filtros, insignias, diagramas, navegación y botones; los fondos personalizados de figuras y notas adhesivas usan un color de texto calculado por contraste.

La app conserva el estado de navegación y edición al alternar claro/oscuro.

## Validación

Las pruebas cubren agrupación mixta y copia independiente, redimensionado con cancelar/deshacer/rehacer, serialización de bocetos, contraste de rellenos, persistencia de requerimientos con hijos, rechazo de padres de otros proyectos y un ciclo completo de herramientas de API con transporte simulado. También se comprueban formularios, bocetos en pantallas pequeñas, cambio de tema y que seleccionar un proveedor alternativo no abra Gemini Live.

Falta validación con credenciales reales de DeepSeek/MiMo y ejecución del modelo local en el dispositivo objetivo. Las pruebas de transporte no validan disponibilidad o cuota de las cuentas, rendimiento del modelo ni permisos nativos de micrófono/dictado.

Resultados de esta implementación (16 de septiembre de 2026):

- Suite completa tras las mejoras de creación y bento: 131 pruebas aprobadas.
- La configuración de Live Thinking, los estados de interacción y la revisión de artefactos se describen en [Creación con IA y bento](creacion-ia-y-bento.md).
- `flutter analyze --no-pub --no-fatal-infos`: sin errores ni advertencias de Dart; quedan avisos de estilo sobre llaves en condicionales.
- Compilación debug de macOS verificada. Xcode muestra advertencias del código nativo de micrófono y de las fases de firma/empaquetado de Gemma; la compilación concluye correctamente.
