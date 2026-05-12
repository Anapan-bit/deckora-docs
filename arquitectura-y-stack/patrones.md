# Patrones de diseño aplicados

## Arquitectura macro: Cliente-servidor con SPA + API REST

- **Frontend (React + Vite):** SPA con enrutamiento client-side mediante `react-router-dom`. Desplegada en Vercel con CDN global.
- **Backend (Node.js + Express):** API REST stateless. Autenticación por JWT validado contra Supabase. Desplegada en Render.
- **Autenticación (Supabase Auth):** servicio externo tipo SaaS que emite y valida los tokens. El frontend obtiene el access token y lo envía al backend en el header `Authorization: Bearer <token>`.
- **Base de datos (Supabase Postgres):** PostgreSQL administrado en la nube, con extensión `pgvector` para almacenar embeddings de cartas (recomendaciones IA).
- **Servicios externos:** Scryfall API (catálogo de cartas, sincronizado por seeder), OpenAI API (embeddings y asistente IA).

Flujo simplificado de una petición autenticada:

```
[Usuario] ──> [Frontend SPA]
              │
              │ supabase.auth.signInWithPassword()
              ▼
              [Supabase Auth] ──> devuelve access_token (JWT)
              │
              │ fetch a https://deckora-api.onrender.com/...
              │ Authorization: Bearer <access_token>
              ▼
              [Backend Express]
              │
              │ middleware auth → valida JWT contra Supabase
              │ middleware validate → valida payload con schema
              │ middleware requirePerfil → valida rol del usuario
              │ controller → orquesta llamadas al service
              │ service → ejecuta lógica de negocio
              │ repository → habla con Supabase Postgres
              ▼
              [Supabase Postgres] ──> devuelve datos
```

---

## Patrones en el backend

### 1. Service Layer

La lógica de negocio se separa en `services/` y los controladores (Express routes) solo orquestan: reciben el request validado, llaman al service correspondiente y devuelven la respuesta HTTP. Los services no conocen `req` ni `res`.

**Razón:** la capa de servicios es testeable independientemente del framework HTTP y reutilizable desde otros entry points (por ejemplo, un script de mantenimiento o un job).

**Ejemplos en Deckora:**

- `mazos.service.js`: contiene la lógica para crear, validar y modificar mazos (validar cantidad de cartas según formato, restricciones de Commander como singleton e identidad de color, etc.).
- `enfrentamientos.service.js`: maneja la transición de estados de un enfrentamiento (`pendiente` → `en_curso` → `finalizado`) y el cálculo de puntos por mesa.
- `cartas.service.js`: orquesta la búsqueda en la tabla local cacheada desde Scryfall.

### 2. Repository Pattern

El acceso a datos se centraliza en `repositories/` (una capa por entidad principal). Los services llaman a métodos del repository en lugar de hablar directamente con el cliente de base de datos.

**Razón:** desacopla la lógica de negocio del proveedor concreto de persistencia. Si en el futuro se migra desde Supabase a otro PostgreSQL administrado, o se introduce un ORM distinto, los cambios quedan contenidos en la capa de repositorios.

**Ejemplos en Deckora:**

- `mazos.repository.js`: expone métodos como `buscarPorId(id)`, `listarDelUsuario(usuarioId)`, `agregarCarta(mazoId, cartaId, cantidad)`. Internamente usa el cliente de Supabase.
- `enfrentamientos.repository.js`: métodos como `actualizarEstado(id, estado)`, `registrarResultado(id, resultados)`.

### 3. DTO + validación con Zod

Las requests pasan por schemas Zod antes de llegar a los services. Cada endpoint define su schema en un archivo `<dominio>.schema.js`. El middleware `validate(schema)` rechaza la petición con HTTP 400 y mensaje claro si el payload no cumple las reglas.

**Razón:** validación temprana, mensajes de error consistentes y declarativos, tipado implícito de los DTOs en los services.

**Ejemplos en Deckora:**

- `auth.schema.js`: define `signupSchema` (correo, contraseña, nombre de usuario, rol válido) y `loginSchema`.
- `mazos.schema.js`: define `crearMazoSchema` (nombre obligatorio, formato del enum `FORMATOS`, descripción opcional, público opcional) y `agregarCartaMazoSchema` (cantidad entera positiva, flag de comandante).
- `torneos.schema.js`: define `crearTorneoSchema` (fecha en futuro, cupo positivo, formato válido) e `inscribirSchema`.

### 4. Middleware Chain

Las rutas componen una cadena de middlewares antes de llegar al controlador. El orden importa: autenticación → validación de schema → autorización por rol → controlador.

**Razón:** separación de responsabilidades transversales (auth, validación, autorización) en piezas reutilizables.

**Ejemplo de Deckora:**

```js
router.post(
  '/',
  auth,                              // 1. Verifica JWT y carga el usuario
  validate(crearMazoSchema),         // 2. Valida el payload
  requirePerfil('jugador'),          // 3. Verifica que el rol sea jugador
  mazosController.crear              // 4. Ejecuta la lógica
);
```

### 5. Organización modular por dominio

El backend está organizado por dominio funcional (cartas, mazos, torneos, etc.) y cada uno agrupa sus propios archivos: routes, controller, service, schema, repository.

**Razón:** alto cohesión por feature, bajo acoplamiento entre dominios, fácil ubicar todo lo relacionado a una entidad.

---

## Patrones en el frontend

### 6. Composición de componentes + custom hooks

Los componentes se mantienen presentacionales y la lógica se extrae a hooks reutilizables. Un componente recibe datos por props y dispara callbacks; el hook encapsula efectos, llamadas a servicios y estado.

**Razón:** componentes más simples de testear y reutilizar, lógica compartida sin herencia ni HOC.

**Ejemplos en Deckora:**

- `useAuth()`: expone `user`, `rol`, `loading`, `login`, `signup`, `logout`. Consumido en cualquier componente que necesite auth.
- `useDebounce(value, delay)`: usado en el buscador de cartas del deck builder para no disparar una petición por cada tecla.
- `useGeolocation()`: usado en el mapa de tiendas para solicitar la ubicación del navegador.
- `useMediaQuery(query)`: usado para condicionar layouts responsive.

### 7. Organización modular + componentes compartidos

En lugar de Atomic Design estricto, se adoptó un enfoque híbrido: cada feature vive en su propio módulo (`modules/<feature>/`) con sus pages, componentes específicos y rutas; los componentes UI base y los componentes de dominio reutilizables viven en raíz (`components/ui/`, `components/domain/`).

**Razón:** Atomic Design puro (atoms / molecules / organisms) resultaba ambiguo para distinguir entre un Badge genérico y un FormatBadge específico de MTG. El esquema modular hace más explícita la frontera entre lo reutilizable y lo específico de un feature.

**Equivalencias aproximadas con Atomic Design:**

- `components/ui/` ≈ atoms + molecules genéricos (Button, Input, Modal, Badge, Tabs).
- `components/domain/` ≈ moléculas y organismos del dominio de la aplicación (MTGCard, DeckList, PodTable, MapaTiendas).
- `components/layout/` ≈ templates (Navbar, Sidebar, Footer, AppLayout).
- `modules/<feature>/pages/` ≈ pages.

### 8. Context API + Provider Pattern

Los estados verdaderamente globales (autenticación) se exponen mediante React Context con un provider en la raíz de la app y un hook consumidor.

**Razón:** evita prop drilling sin la complejidad de Redux. Para el alcance del proyecto, Context es suficiente.

**Ejemplo en Deckora:**

- `AuthProvider` envuelve toda la app. Mantiene el estado de sesión, escucha cambios de Supabase Auth con `onAuthStateChange` y delega operaciones en `auth.service.js`. Se consume mediante `useAuth()`.

### 9. Service Layer en el frontend

Tal como en el backend, las llamadas HTTP se encapsulan en archivos `services/<dominio>.service.js`. Los componentes nunca hacen `fetch` directo: importan funciones del service.

**Razón:** centralizar el manejo de errores, headers de autenticación y forma de los datos. Si cambia el contrato de la API, se actualiza en un solo lugar.

**Ejemplos en Deckora:**

- `auth.service.js`: `login`, `signup`, `logout`, `getMe`, `recuperarPassword`.
- `mazos.service.js`: `listarMisMazos`, `crearMazo`, `obtenerMazo`, `agregarCartaAMazo`, `validarMazo`.
- `cartas.service.js`: `buscarCartas(query)`, `obtenerCarta(scryfallId)`.

Todos los services consumen el helper `api.js`, que envuelve `fetch` adjuntando automáticamente el JWT de Supabase y normalizando errores.

### 10. Protected Routes y autorización basada en roles

El componente `<ProtectedRoute requireRol="...">` envuelve las rutas privadas. Verifica sesión y rol antes de renderizar el contenido; en caso contrario redirige a `/login` o `/forbidden`.

**Razón:** la lógica de autorización en el frontend queda declarativa y centralizada en la configuración de rutas, no dispersa en cada componente.

**Ejemplo de Deckora:**

```jsx
<Route
  path="/mazos"
  element={
    <ProtectedRoute requireRol="jugador">
      <MisMazos />
    </ProtectedRoute>
  }
/>
```

### 11. Composición de rutas por módulo

Cada módulo del frontend exporta su propio fragmento de rutas en `routes.jsx`. El archivo top-level `AppRoutes.jsx` solo importa y compone esos fragmentos.

**Razón:** permite que dos personas trabajen en módulos distintos sin tocar el mismo archivo central, reduciendo conflictos de merge.

### 12. Compound Components

Algunos componentes UI exponen sub-componentes que comparten contexto interno, en lugar de pasar todo por props.

**Ejemplos en Deckora:**

- `<Tabs>` + `<Tabs.Tab eventKey="..." label="..." />`: el Tabs maneja el estado del tab activo internamente.
- `<Modal>` con header, body y footer como children diferenciados.

### 13. Token-based authentication flow

El frontend nunca almacena ni gestiona el JWT manualmente: el SDK de Supabase lo maneja en `localStorage` con auto-refresh. El helper `api.js` lo recupera con `supabase.auth.getSession()` antes de cada petición y lo adjunta al header.

**Razón:** delegar la complejidad del refresh token al SDK oficial elimina toda una clase de bugs de expiración.

---

## Estructura de carpetas (backend)

```
deckora-api/
├── src/
│   ├── modules/
│   │   ├── auth/
│   │   │   ├── auth.routes.js          (rutas: signup, login, me, logout)
│   │   │   ├── auth.controller.js      (orquesta requests)
│   │   │   ├── auth.service.js         (lógica de negocio)
│   │   │   ├── auth.repository.js      (acceso a datos)
│   │   │   └── auth.schema.js          (schemas Zod)
│   │   ├── cartas/
│   │   │   ├── cartas.routes.js
│   │   │   ├── cartas.controller.js
│   │   │   ├── cartas.service.js
│   │   │   └── cartas.repository.js
│   │   ├── colecciones/
│   │   │   ├── colecciones.routes.js
│   │   │   ├── colecciones.controller.js
│   │   │   ├── colecciones.service.js
│   │   │   ├── colecciones.repository.js
│   │   │   └── colecciones.schema.js
│   │   ├── mazos/
│   │   │   ├── mazos.routes.js
│   │   │   ├── mazos.controller.js
│   │   │   ├── mazos.service.js
│   │   │   ├── mazos.repository.js
│   │   │   └── mazos.schema.js
│   │   ├── torneos/
│   │   │   ├── torneos.routes.js
│   │   │   ├── torneos.controller.js
│   │   │   ├── torneos.service.js
│   │   │   ├── torneos.repository.js
│   │   │   └── torneos.schema.js
│   │   ├── rondas/
│   │   │   ├── rondas.routes.js
│   │   │   ├── rondas.controller.js
│   │   │   ├── rondas.service.js
│   │   │   ├── rondas.repository.js
│   │   │   └── rondas.schema.js
│   │   ├── enfrentamientos/
│   │   │   ├── enfrentamientos.routes.js
│   │   │   ├── enfrentamientos.controller.js
│   │   │   ├── enfrentamientos.service.js
│   │   │   ├── enfrentamientos.repository.js
│   │   │   └── enfrentamientos.schema.js
│   │   └── tiendas/
│   │       ├── tiendas.routes.js
│   │       ├── tiendas.controller.js
│   │       ├── tiendas.service.js
│   │       └── tiendas.repository.js
│   │
│   ├── middleware/
│   │   ├── auth.js                     (verifica JWT de Supabase)
│   │   ├── validate.js                 (aplica schema Zod a req.body)
│   │   ├── requirePerfil.js            (autorización por rol)
│   │   └── errorHandler.js             (captura y formatea errores)
│   │
│   ├── lib/
│   │   ├── supabase.js                 (cliente Supabase del servidor)
│   │   └── scryfall.js                 (cliente externo para Scryfall)
│   │
│   ├── config/
│   │   └── env.js                      (validación de variables de entorno)
│   │
│   ├── app.js                          (registra middlewares y módulos)
│   └── server.js                       (entry point, levanta el servidor)
│
├── scripts/
│   └── seedCartas.js                   (poblar la tabla cartas desde Scryfall)
│
├── migrations/                         (gestionadas por Sequelize)
│
├── .env.example
├── .gitignore
├── package.json
└── README.md
```

---

## Estructura de carpetas (frontend)

```
deckora-web/
├── public/
│   └── favicon.svg
│
├── src/
│   ├── assets/
│   │   ├── fonts/
│   │   └── images/
│   │
│   ├── components/                     (compartidos entre módulos)
│   │   ├── layout/
│   │   │   ├── AppLayout.jsx
│   │   │   ├── Navbar.jsx
│   │   │   ├── Sidebar.jsx
│   │   │   ├── Footer.jsx
│   │   │   └── index.js
│   │   ├── ui/                         (atoms + molecules genéricos)
│   │   │   ├── Button.jsx
│   │   │   ├── Card.jsx
│   │   │   ├── Modal.jsx
│   │   │   ├── Input.jsx
│   │   │   ├── Select.jsx
│   │   │   ├── Textarea.jsx
│   │   │   ├── Badge.jsx
│   │   │   ├── Spinner.jsx
│   │   │   ├── EmptyState.jsx
│   │   │   ├── Tabs.jsx
│   │   │   ├── Alert.jsx
│   │   │   ├── Tooltip.jsx
│   │   │   ├── Skeleton.jsx
│   │   │   └── index.js
│   │   └── domain/                     (organismos específicos del dominio MTG)
│   │       ├── MTGCard.jsx
│   │       ├── ManaCost.jsx
│   │       ├── DeckList.jsx
│   │       ├── DeckStats.jsx
│   │       ├── DeckBuilder.jsx
│   │       ├── ColeccionEditor.jsx
│   │       ├── TournamentCard.jsx
│   │       ├── PodTable.jsx
│   │       ├── RoundView.jsx
│   │       ├── MapaTiendas.jsx
│   │       ├── MiniMapaTienda.jsx
│   │       ├── StorePin.jsx
│   │       ├── FormatBadge.jsx
│   │       ├── RoleBadge.jsx
│   │       ├── EstadoBadge.jsx
│   │       ├── CommanderBadge.jsx
│   │       ├── EstadisticasJugador.jsx
│   │       └── index.js
│   │
│   ├── modules/                        (organización por feature)
│   │   ├── identidad/
│   │   │   ├── pages/
│   │   │   │   ├── Login.jsx
│   │   │   │   ├── Registro.jsx
│   │   │   │   ├── RecuperarPassword.jsx
│   │   │   │   ├── PerfilJugador.jsx
│   │   │   │   ├── PerfilOrganizador.jsx
│   │   │   │   ├── PerfilTienda.jsx
│   │   │   │   ├── PerfilRouter.jsx
│   │   │   │   └── Configuracion.jsx
│   │   │   ├── components/
│   │   │   │   ├── SelectorRol.jsx
│   │   │   │   ├── CuentaTab.jsx
│   │   │   │   └── ConfiguracionTiendaTab.jsx
│   │   │   └── routes.jsx
│   │   │
│   │   ├── mazos/
│   │   │   ├── pages/
│   │   │   │   ├── MisColecciones.jsx
│   │   │   │   ├── DetalleColeccion.jsx
│   │   │   │   ├── MisMazos.jsx
│   │   │   │   ├── CrearMazoModal.jsx
│   │   │   │   └── DetalleMazo.jsx
│   │   │   ├── components/
│   │   │   │   ├── BarraAgregarCarta.jsx
│   │   │   │   ├── ModoEdicionMazo.jsx
│   │   │   │   ├── AsistenteIA.jsx
│   │   │   │   └── PanelValidacion.jsx
│   │   │   └── routes.jsx
│   │   │
│   │   ├── torneos/
│   │   │   ├── pages/
│   │   │   │   ├── Cartelera.jsx
│   │   │   │   ├── DetalleTorneo.jsx
│   │   │   │   ├── CrearTorneo.jsx
│   │   │   │   ├── EditarTorneo.jsx
│   │   │   │   └── GestionTorneo.jsx
│   │   │   ├── components/
│   │   │   │   ├── FormularioTorneo.jsx
│   │   │   │   ├── PanelInscripcion.jsx
│   │   │   │   ├── ListaInscritos.jsx
│   │   │   │   └── ReportarResultadoModal.jsx
│   │   │   └── routes.jsx
│   │   │
│   │   ├── mapa/
│   │   │   └── components/
│   │   │       └── SeccionMapaTiendas.jsx
│   │   │
│   │   └── dashboards/
│   │       ├── pages/
│   │       │   ├── Landing.jsx
│   │       │   ├── DashboardJugador.jsx
│   │       │   ├── DashboardOrganizador.jsx
│   │       │   └── DashboardTienda.jsx
│   │       ├── components/
│   │       │   ├── HeroLanding.jsx
│   │       │   ├── FeaturesLanding.jsx
│   │       │   ├── ProfilesLanding.jsx
│   │       │   ├── CTALanding.jsx
│   │       │   ├── BloqueResumen.jsx
│   │       │   └── StatsRapidas.jsx
│   │       └── routes.jsx
│   │
│   ├── pages/                          (páginas globales fuera de módulos)
│   │   ├── NotFound.jsx
│   │   ├── Forbidden.jsx
│   │   └── PlaceholderPage.jsx
│   │
│   ├── hooks/
│   │   ├── useAuth.js
│   │   ├── useApi.js
│   │   ├── useGeolocation.js
│   │   ├── useDebounce.js
│   │   └── useMediaQuery.js
│   │
│   ├── context/
│   │   └── AuthContext.jsx
│   │
│   ├── services/
│   │   ├── supabase.js                 (cliente Supabase del navegador)
│   │   ├── api.js                      (helper fetch con JWT)
│   │   ├── auth.service.js
│   │   ├── cartas.service.js
│   │   ├── colecciones.service.js
│   │   ├── mazos.service.js
│   │   ├── torneos.service.js
│   │   ├── rondas.service.js
│   │   ├── enfrentamientos.service.js
│   │   ├── tiendas.service.js
│   │   └── usuarios.service.js
│   │
│   ├── styles/
│   │   ├── tokens.css                  (variables :root)
│   │   ├── base.css                    (reset y body)
│   │   ├── typography.css              (Google Fonts y escala)
│   │   ├── components.css              (estilos de todos los componentes)
│   │   └── index.css                   (entry point)
│   │
│   ├── utils/
│   │   ├── constants.js                (enums de la base de datos)
│   │   ├── formatters.js               (fechas, números, costos de maná)
│   │   ├── validators.js               (validaciones de formularios)
│   │   └── deck-helpers.js             (agrupar cartas por tipo, calcular curva)
│   │
│   ├── routes/
│   │   ├── AppRoutes.jsx               (composición de rutas por módulo)
│   │   └── ProtectedRoute.jsx
│   │
│   ├── App.jsx
│   └── main.jsx
│
├── .env.example
├── .eslintrc.cjs
├── .gitignore
├── .prettierrc
├── DECKORA_FRONTEND.md                 (especificación técnica del frontend)
├── PROJECT_TODO.md                     (estado del proyecto y tareas)
├── README.md
├── index.html
├── jsconfig.json
├── package.json
└── vite.config.js
```

---

## Resumen de patrones aplicados por capa

| Capa | Patrón | Implementación en Deckora |
|---|---|---|
| Arquitectura | Cliente-Servidor + REST | SPA en Vercel ↔ API en Render |
| Arquitectura | Stateless con JWT | Tokens emitidos por Supabase Auth |
| Backend | Service Layer | `<dominio>.service.js` por feature |
| Backend | Repository Pattern | `<dominio>.repository.js` por entidad |
| Backend | DTO + Validación | Schemas Zod en `<dominio>.schema.js` |
| Backend | Middleware Chain | auth, validate, requirePerfil |
| Backend | Organización modular | `modules/<dominio>/` |
| Frontend | Composición + Hooks | `useAuth`, `useDebounce`, etc. |
| Frontend | Modular + UI compartida | `modules/` + `components/{ui,domain,layout}` |
| Frontend | Context + Provider | `AuthContext` y `useAuth()` |
| Frontend | Service Layer | `<dominio>.service.js` (espejo del backend) |
| Frontend | Protected Routes | `<ProtectedRoute requireRol="...">` |
| Frontend | Rutas por módulo | `modules/<feature>/routes.jsx` |
| Frontend | Compound Components | `<Tabs>` con `<Tabs.Tab>`, Modal con sub-secciones |
| Frontend | Token-based auth | SDK de Supabase + helper `api.js` |
