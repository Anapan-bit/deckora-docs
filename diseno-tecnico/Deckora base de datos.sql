CREATE TABLE "usuarios" (
  "id" uuid PRIMARY KEY,
  "nombre_usuario" varchar NOT NULL,
  "correo" varchar UNIQUE NOT NULL,
  "rol" varchar NOT NULL,
  "activo" boolean DEFAULT true,
  "created_at" timestamp DEFAULT (now())
);

CREATE TABLE "jugadores" (
  "usuario_id" uuid PRIMARY KEY,
  "formato_preferido" varchar
);

CREATE TABLE "organizadores" (
  "usuario_id" uuid PRIMARY KEY,
  "descripcion" text,
  "sitio_web" varchar,
  "verificado" boolean DEFAULT false
);

CREATE TABLE "tiendas" (
  "usuario_id" uuid PRIMARY KEY,
  "nombre_tienda" varchar,
  "direccion" varchar,
  "numero_telefono" varchar,
  "horario_apertura" varchar,
  "latitud" float,
  "longitud" float
);

CREATE TABLE "cartas" (
  "id" uuid PRIMARY KEY,
  "scryfall_id" varchar UNIQUE NOT NULL,
  "nombre" varchar NOT NULL,
  "tipo" varchar,
  "resistencia" varchar,
  "fuerza" varchar,
  "texto" text,
  "costo_mana" varchar,
  "imagen_url" varchar,
  "set_codigo" varchar,
  "es_tierra_basica" boolean DEFAULT false,
  "embedding" vector(1536)
);

CREATE TABLE "colecciones" (
  "id" uuid PRIMARY KEY,
  "usuario_id" uuid,
  "nombre" varchar NOT NULL,
  "fecha_creacion" timestamp DEFAULT (now()),
  "activo" boolean DEFAULT true
);

CREATE TABLE "coleccion_cartas" (
  "id" uuid PRIMARY KEY,
  "coleccion_id" uuid,
  "carta_id" uuid,
  "cantidad" integer DEFAULT 1,
  "es_foil" boolean DEFAULT false
);

CREATE TABLE "mazos" (
  "id" uuid PRIMARY KEY,
  "usuario_id" uuid,
  "nombre" varchar NOT NULL,
  "formato" varchar NOT NULL,
  "descripcion" text,
  "publico" boolean DEFAULT false,
  "slug" varchar UNIQUE,
  "actualizado_en" timestamp DEFAULT (now()),
  "fecha_creacion" timestamp DEFAULT (now())
);

CREATE TABLE "mazo_cartas" (
  "id" uuid PRIMARY KEY,
  "mazo_id" uuid,
  "carta_id" uuid,
  "cantidad" integer DEFAULT 1,
  "es_comandante" boolean DEFAULT false
);

CREATE TABLE "torneos" (
  "id" uuid PRIMARY KEY,
  "organizador_id" uuid,
  "nombre" varchar NOT NULL,
  "formato" varchar NOT NULL,
  "estado" varchar DEFAULT 'pendiente',
  "fecha" timestamp NOT NULL,
  "ubicacion" varchar,
  "latitud" float,
  "longitud" float,
  "cupo_maximo" integer,
  "precio" float DEFAULT 0,
  "created_at" timestamp DEFAULT (now())
);

CREATE TABLE "inscripciones" (
  "id" uuid PRIMARY KEY,
  "torneo_id" uuid,
  "usuario_id" uuid,
  "mazo_id" uuid,
  "fecha_inscripcion" timestamp DEFAULT (now()),
  "confirmado" boolean DEFAULT false
);

CREATE TABLE "snapshot_mazo_inscripcion" (
  "id" uuid PRIMARY KEY,
  "inscripcion_id" uuid,
  "carta_id" uuid,
  "cantidad" integer NOT NULL,
  "es_foil" boolean DEFAULT false
);

CREATE TABLE "rondas" (
  "id" uuid PRIMARY KEY,
  "torneo_id" uuid,
  "numero_ronda" integer NOT NULL,
  "tipo_ronda" varchar
);

CREATE TABLE "enfrentamientos" (
  "id" uuid PRIMARY KEY,
  "ronda_id" uuid,
  "numero_mesa" integer,
  "estado" varchar DEFAULT 'pendiente'
);

CREATE TABLE "enfrentamiento_participantes" (
  "id" uuid PRIMARY KEY,
  "enfrentamiento_id" uuid,
  "inscripcion_id" uuid,
  "puntos_obtenidos" integer DEFAULT 0,
  "resultado" varchar
);

CREATE TABLE "estadisticas" (
  "usuario_id" uuid PRIMARY KEY,
  "partidas_ganadas" integer DEFAULT 0,
  "partidas_perdidas" integer DEFAULT 0,
  "partidas_empatadas" integer DEFAULT 0,
  "torneos_participados" integer DEFAULT 0,
  "ultima_actualizacion" timestamp DEFAULT (now())
);

CREATE UNIQUE INDEX ON "coleccion_cartas" ("coleccion_id", "carta_id", "es_foil");

CREATE UNIQUE INDEX ON "mazo_cartas" ("mazo_id", "carta_id");

CREATE UNIQUE INDEX ON "inscripciones" ("torneo_id", "usuario_id");

CREATE UNIQUE INDEX ON "inscripciones" ("torneo_id", "mazo_id");

COMMENT ON COLUMN "usuarios"."rol" IS 'CHECK: jugador | organizador | tienda';

COMMENT ON COLUMN "jugadores"."formato_preferido" IS 'CHECK: COMMANDER | STANDARD | MODERN | PIONEER | LEGACY';

COMMENT ON COLUMN "tiendas"."latitud" IS 'Requerido para búsqueda por proximidad';

COMMENT ON COLUMN "tiendas"."longitud" IS 'Requerido para búsqueda por proximidad';

COMMENT ON COLUMN "cartas"."scryfall_id" IS 'UUID de Scryfall para sincronización y deduplicación';

COMMENT ON COLUMN "cartas"."imagen_url" IS 'URL de Scryfall, nunca imagen local';

COMMENT ON COLUMN "cartas"."set_codigo" IS 'Código del set de esta impresión, ej: DSK, BLB';

COMMENT ON COLUMN "cartas"."embedding" IS 'pgvector: para recomendaciones con IA';

COMMENT ON COLUMN "colecciones"."usuario_id" IS 'Solo jugadores pueden poseer colecciones';

COMMENT ON COLUMN "mazos"."usuario_id" IS 'Solo jugadores pueden crear mazos';

COMMENT ON COLUMN "mazos"."formato" IS 'CHECK: COMMANDER | STANDARD | MODERN | PIONEER | LEGACY';

COMMENT ON COLUMN "mazos"."slug" IS 'Para URLs públicas tipo /m/sol-ring-edh';

COMMENT ON COLUMN "mazo_cartas"."es_comandante" IS 'Solo aplica en formato Commander';

COMMENT ON COLUMN "torneos"."organizador_id" IS 'Middleware valida que sea organizador o tienda';

COMMENT ON COLUMN "torneos"."formato" IS 'CHECK: COMMANDER | STANDARD | MODERN | PIONEER | LEGACY';

COMMENT ON COLUMN "torneos"."estado" IS 'CHECK: pendiente | en_curso | finalizado | cancelado';

COMMENT ON COLUMN "inscripciones"."usuario_id" IS 'Solo jugadores pueden inscribirse';

COMMENT ON COLUMN "inscripciones"."mazo_id" IS 'El mazo inscrito. La validación por formato se corre aquí (Strategy)';

COMMENT ON COLUMN "rondas"."tipo_ronda" IS 'CHECK: swiss | eliminacion_directa | final';

COMMENT ON COLUMN "enfrentamientos"."estado" IS 'CHECK: pendiente | en_curso | finalizado';

COMMENT ON COLUMN "enfrentamiento_participantes"."resultado" IS 'CHECK: ganador | perdedor | empate | pendiente';

ALTER TABLE "jugadores" ADD FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "organizadores" ADD FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "tiendas" ADD FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "colecciones" ADD FOREIGN KEY ("usuario_id") REFERENCES "jugadores" ("usuario_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "coleccion_cartas" ADD FOREIGN KEY ("coleccion_id") REFERENCES "colecciones" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "coleccion_cartas" ADD FOREIGN KEY ("carta_id") REFERENCES "cartas" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "mazos" ADD FOREIGN KEY ("usuario_id") REFERENCES "jugadores" ("usuario_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "mazo_cartas" ADD FOREIGN KEY ("mazo_id") REFERENCES "mazos" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "mazo_cartas" ADD FOREIGN KEY ("carta_id") REFERENCES "cartas" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "torneos" ADD FOREIGN KEY ("organizador_id") REFERENCES "usuarios" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "inscripciones" ADD FOREIGN KEY ("torneo_id") REFERENCES "torneos" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "inscripciones" ADD FOREIGN KEY ("usuario_id") REFERENCES "jugadores" ("usuario_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "inscripciones" ADD FOREIGN KEY ("mazo_id") REFERENCES "mazos" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "snapshot_mazo_inscripcion" ADD FOREIGN KEY ("inscripcion_id") REFERENCES "inscripciones" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "snapshot_mazo_inscripcion" ADD FOREIGN KEY ("carta_id") REFERENCES "cartas" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "rondas" ADD FOREIGN KEY ("torneo_id") REFERENCES "torneos" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "enfrentamientos" ADD FOREIGN KEY ("ronda_id") REFERENCES "rondas" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "enfrentamiento_participantes" ADD FOREIGN KEY ("enfrentamiento_id") REFERENCES "enfrentamientos" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "enfrentamiento_participantes" ADD FOREIGN KEY ("inscripcion_id") REFERENCES "inscripciones" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "estadisticas" ADD FOREIGN KEY ("usuario_id") REFERENCES "jugadores" ("usuario_id") DEFERRABLE INITIALLY IMMEDIATE;
