# 🛡️ Política de Seguridad — ProjectJaina_VisualShop

**Proyecto:** Project Jaina  
**Estándar de Seguridad:** Staff Software Engineer L9 (Mythos 5)  
**Fecha de Actualización:** 10 de Octubre de 2026  

---

## 1. Alcance y Filosofía de Seguridad

La seguridad de **ProjectJaina_VisualShop** se fundamenta en el aislamiento estricto del entorno de ejecución de Lua 5.1 dentro del cliente World of Warcraft 3.3.5a (Build 12340) y en la validación autoritativa en el servidor.

---

## 2. Principios de Blindaje de Código

1. **Aislamiento de FrameXML y Anti-Taint:**
   - Las funciones que interactúan con botones de acción protegidos o macros de combate no contaminan las variables de entorno global seguras.
   - Se evita estrictamente la modificación de tablas globales del sistema sin nombres de espacio propios (`PJ_*` o nombres de addon).
2. **Límite de Red y Prevención de Desbordamiento:**
   - La API `SendAddonMessage` está restringida a un máximo absoluto de **255 bytes por paquete**. Todo payload emitido se fragmenta o comprime en estructuras compactas.
   - Prefijo auditado: `WPVS`.
3. **Validación Autoritativa en Servidor:**
   - El cliente de interfaz es tratado como un medio de presentación potencialmente no confiable. Ninguna transacción de ítems, progreso, monedas o recompensas es decidida por el cliente; el servidor Eluna / C++ (`59_SpellVisualCatalog.lua y tablas de acore_characters`) valida y aplica los cambios en MySQL.
4. **Higiene de Strings y Sanitización:**
   - Toda entrada de usuario proveniente de cajas de texto (`EditBox`) o comandos slash (`/vshop, /visualshop`) es limpiada contra inyecciones de secuencias de escape y caracteres nulos.

---

## 3. Reporte Responsable de Vulnerabilidades

Si descubres una vulnerabilidad de seguridad o un vector de explotación en este AddOn:
- **No lo divulgues públicamente.**
- Notifícalo de inmediato a través del canal privado de ingeniería en el portal oficial: [Project Jaina Contacto](https://darckrovert.github.io/ProjectJaina_Web/).
- El equipo técnico investigará y aplicará el parche correctivo de forma expedita.
