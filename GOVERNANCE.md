# 🏛️ Modelo de Gobernanza del Proyecto — Project Jaina Visual Shop

**Versión del Documento:** 1.0.1  
**Fecha de Entrada en Vigor:** 10 de Octubre de 2026  
**Líder del Proyecto & Autor:** DarckRovert (Ingame: `Elnazzareno`)  
**Staff AI Engineer:** Antigravity L9 (Mythos 5)  
**Servidor Destino:** [Project Jaina](https://darckrovert.github.io/ProjectJaina_Web/)  
**Entorno de Ejecución:** World of Warcraft 3.3.5a (Build 12340) | Interfaz: `30300`  

---

## 1. Misión y Alcance

**ProjectJaina_VisualShop** es un componente oficial de la suite de interfaz de usuario de **Project Jaina**.
Tienda estética in-game de transfiguraciones, auras visuales y efectos cosméticos con vista previa 3D de modelos y compra autoritativa en el servidor.

### Objetivos Primordiales del Sistema:
1. **Rendimiento Extremo (Cabinas de Internet & Equipos Modestos):**
   - Ejecución fluida a 60 FPS estables sin micro-parones en resoluciones desde $800\times600$ hasta $1920\times1080$.
   - Aislamiento estricto de eventos en `OnUpdate` para prevenir saturación de CPU.
2. **Seguridad de Red y Límite Inviolable de Paquetes:**
   - Todo mensaje transmitido mediante `SendAddonMessage` respeta el límite estricto de **255 bytes por paquete** de la versión 3.3.5a.
   - Prefijo de Red Registrado: `WPVS`.
3. **Persistencia Segura e Idempotencia:**
   - La persistencia de datos utiliza variables guardadas (`VisualShopDB`) y/o sincronización atómica con el backend del servidor (`59_SpellVisualCatalog.lua y tablas de acore_characters`).
   - Cero pérdida de datos ante desconexiones intempestivas o reinicios con sistemas tipo *Deep Freeze*.
4. **Cumplimiento de la Política de Blizzard (Blizzard Custom UI Policy 2009):**
   - Software 100% gratuito, libre de código malicioso, sin ingeniería inversa ni modificación de binarios ejecutables (`WoW.exe`).

---

## 2. Estructura de Roles y Responsabilidades

El proyecto se rige bajo un modelo de **Liderazgo Técnico Centralizado y Revisión por Pares**:

```
       ┌─────────────────────────────────────────┐
       │   Líder del Proyecto (Project Lead)     │
       │     DarckRovert (Elnazzareno)            │
       └────────────────────┬────────────────────┘
                            │
       ┌────────────────────▼────────────────────┐
       │     Staff AI & Arquitectura de Core     │
       │        Antigravity L9 (Mythos 5)        │
       └────────────────────┬────────────────────┘
                            │
       ┌────────────────────▼────────────────────┐
       │      Equipo de Desarrollo y Staff       │
       │   (Core Eluna, Addon Lua, Moderación)   │
       └─────────────────────────────────────────┘
```

### 2.1. Project Lead (Líder del Proyecto)
- **Titular:** DarckRovert (Elnazzareno).
- **Atribuciones:**
  - Control de la visión arquitectónica, experiencia de usuario y compatibilidad.
  - Aprobación y fusión final de código en la rama `main` del repositorio oficial.
  - Firma y liberación de versiones oficiales estables.
  - Veto técnico sobre cambios que comprometan la estabilidad del cliente o el rendimiento del juego.

### 2.2. Staff AI & Desarrolladores
- **Responsabilidades:**
  - Mantenimiento del código fuente en Lua 5.1 y FrameXML compatible con WotLK 3.3.5a.
  - Verificación de no-taint en subsistemas protegidos de Blizzard.
  - Mantenimiento de la integridad documental y sincronización bidireccional cliente-servidor.

---

## 3. Flujo de Desarrollo, Cambios y RFCs

1. **Ramas de Trabajo:** Todo desarrollo se realiza en ramas de características (`feature/*` o `fix/*`) desprendidas de `main`.
2. **Revisión de Código Obligatoria:** Ningún cambio se incorpora sin revisión de sintaxis Lua estricta y prueba empírica en el cliente de prueba.
3. **Prohibición de APIs de Retail:** Queda estrictamente vetado el uso de APIs no existentes en 3.3.5a (`SetColorTexture`, `C_Timer.After` sin polyfill, `AnimationGroup` no compatibles).

---

## 4. Contacto y Reporte de Incidencias

Las incidencias técnicas, propuestas de mejora y reportes de seguridad deben remitirse a través de los canales oficiales:
* **Portal Web Oficial:** [https://darckrovert.github.io/ProjectJaina_Web/](https://darckrovert.github.io/ProjectJaina_Web/)
* **Repositorio GitHub:** [https://github.com/DarckRovert/ProjectJaina_VisualShop](https://github.com/DarckRovert/ProjectJaina_VisualShop)
