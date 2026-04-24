import { authFetch } from '../auth/http';
import type {
  DetectionClassType,
  DetectionGeometry,
  DetectionSearchRequest,
  DetectionSearchResponse,
  DetectionSeverity,
  DetectionSummary,
  GeoJSONFeature,
  GeoJSONFeatureCollection,
  GeometryMode,
} from '../../entities/detection/types';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS !== 'false';
const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? '';
const QUERY_ENDPOINT = import.meta.env.VITE_DETECTIONS_QUERY_ENDPOINT ?? '/v1/detections:query';

const MOCK_DETECTIONS: DetectionSummary[] = [
  {
    id: 'det-1',
    flightId: 'flight-1',
    classType: 'fire',
    type: 'fire',
    status: 'active',
    score: 0.82,
    severity: 'high',
    title: 'Пожар 1',
    description: 'Точечная детекция пожара рядом с дорогой.',
    detectedAt: '2026-04-19T15:30:00Z',
    lastDetectionAt: '2026-04-19T15:30:00Z',
    imagePath: 'https://example.com/fire-1.jpg',
    centroid: { lat: 60.1234, lon: 30.5678 },
    geometry: {
      type: 'Point',
      coordinates: [30.5678, 60.1234],
    },
    stats: { commentsCount: 2, eventsCount: 5 },
  },
  {
    id: 'det-2',
    flightId: 'flight-2',
    classType: 'infection',
    type: 'infection',
    status: 'active',
    score: 0.64,
    severity: 'medium',
    title: 'Заражение 1',
    description: 'Полигон зараженного участка леса.',
    detectedAt: '2026-04-15T11:30:00Z',
    lastDetectionAt: '2026-04-15T11:30:00Z',
    imagePath: 'https://example.com/infection-1.jpg',
    centroid: { lat: 60.12, lon: 30.74 },
    geometry: {
      type: 'Polygon',
      coordinates: [[
        [30.70, 60.09],
        [30.78, 60.09],
        [30.78, 60.15],
        [30.70, 60.15],
        [30.70, 60.09],
      ]],
    },
    stats: { commentsCount: 1, eventsCount: 4 },
  },
  {
    id: 'det-3',
    flightId: 'flight-3',
    classType: 'logging',
    type: 'logging',
    status: 'active',
    score: 0.51,
    severity: 'medium',
    title: 'Вырубка 1',
    description: 'Мультиполигон по участкам вырубки.',
    detectedAt: '2026-04-12T08:20:00Z',
    lastDetectionAt: '2026-04-12T08:20:00Z',
    imagePath: 'https://example.com/logging-1.jpg',
    centroid: { lat: 60.30, lon: 30.90 },
    geometry: {
      type: 'MultiPolygon',
      coordinates: [
        [[
          [30.88, 60.29],
          [30.92, 60.29],
          [30.92, 60.32],
          [30.88, 60.32],
          [30.88, 60.29],
        ]],
        [[
          [30.95, 60.30],
          [30.98, 60.30],
          [30.98, 60.33],
          [30.95, 60.33],
          [30.95, 60.30],
        ]],
      ],
    },
    stats: { commentsCount: 1, eventsCount: 3 },
  },
  {
    id: 'det-4',
    flightId: 'flight-4',
    classType: 'fire',
    type: 'fire',
    status: 'active',
    score: 0.95,
    severity: 'critical',
    title: 'Пожар 2',
    description: 'Критическая точка возгорания.',
    detectedAt: '2026-04-17T18:45:00Z',
    lastDetectionAt: '2026-04-17T18:45:00Z',
    imagePath: 'https://example.com/fire-2.jpg',
    centroid: { lat: 60.02, lon: 30.82 },
    geometry: {
      type: 'Point',
      coordinates: [30.82, 60.02],
    },
    stats: { commentsCount: 3, eventsCount: 7 },
  },
  {
    id: 'det-5',
    flightId: 'flight-5',
    classType: 'infection',
    type: 'infection',
    status: 'active',
    score: 0.21,
    severity: 'low',
    title: 'Заражение 2',
    description: 'Низкий риск, старая детекция.',
    detectedAt: '2026-03-28T14:20:00Z',
    lastDetectionAt: '2026-03-28T14:20:00Z',
    imagePath: 'https://example.com/infection-2.jpg',
    centroid: { lat: 60.21, lon: 30.38 },
    geometry: {
      type: 'Polygon',
      coordinates: [[
        [30.34, 60.18],
        [30.42, 60.18],
        [30.42, 60.24],
        [30.34, 60.24],
        [30.34, 60.18],
      ]],
    },
    stats: { commentsCount: 0, eventsCount: 1 },
  },
];

type BackendDetectionsQueryRequest = {
  classes?: string[];
  geom?: GeometryMode;
  bbox?: [number, number, number, number];
  min_score?: number;
  max_score?: number;
  since?: string;
  until?: string;
  limit?: number;
};

function resolveApiUrl(path: string) {
  if (/^https?:\/\//i.test(path)) {
    return path;
  }

  return `${API_BASE_URL}${path}`;
}

function getJsonHeaders() {
  return {
    'Content-Type': 'application/json',
    Accept: 'application/geo+json, application/json',
  };
}

function expandBackendClasses(classes: DetectionClassType[]) {
  const result = new Set<string>();

  classes.forEach((classType) => {
    result.add(classType);

    if (classType === 'infection') {
      result.add('disease');
    }
  });

  return Array.from(result);
}

function buildBackendPayload(payload: DetectionSearchRequest): BackendDetectionsQueryRequest {
  return {
    classes: payload.classes.length > 0 ? expandBackendClasses(payload.classes) : undefined,
    geom: payload.geom ?? 'auto',
    bbox: payload.bbox
      ? [payload.bbox.minLon, payload.bbox.minLat, payload.bbox.maxLon, payload.bbox.maxLat]
      : undefined,
    min_score: payload.minScore,
    // Поле уже отправляем из фронта; если backend пока его игнорирует, ниже есть client-side post-filter.
    max_score: payload.maxScore,
    since: payload.period?.from,
    // Аналогично max_score: поле подготовлено для контракта, но UI дополнительно фильтрует ответ локально.
    until: payload.period?.to,
    limit: payload.limit ?? 500,
  };
}

function normalizeSeverity(value: unknown, score: number): DetectionSeverity {
  if (value === 'low' || value === 'medium' || value === 'high' || value === 'critical') {
    return value;
  }

  const rawNumeric = typeof value === 'number' ? value : Number(value ?? score);
  const numeric = rawNumeric > 1 ? rawNumeric / 10 : rawNumeric;

  if (numeric >= 0.9) {
    return 'critical';
  }
  if (numeric >= 0.7) {
    return 'high';
  }
  if (numeric >= 0.4) {
    return 'medium';
  }
  return 'low';
}

function normalizeClassType(value: unknown): DetectionClassType {
  if (value === 'fire') {
    return 'fire';
  }

  if (value === 'logging' || value === 'deforestation' || value === 'cutting') {
    return 'logging';
  }

  return 'infection';
}

function normalizeScore(value: unknown) {
  const numeric = Number(value ?? 0);

  if (!Number.isFinite(numeric)) {
    return 0;
  }

  return numeric > 1 ? Number((numeric / 10).toFixed(3)) : numeric;
}

function collectGeometryPoints(geometry: DetectionGeometry | null | undefined): Array<[number, number]> {
  if (!geometry) {
    return [];
  }

  if (geometry.type === 'Point') {
    return [geometry.coordinates];
  }

  if (geometry.type === 'Polygon') {
    return geometry.coordinates.flat() as Array<[number, number]>;
  }

  return geometry.coordinates.flat(2) as Array<[number, number]>;
}

function getCentroid(geometry: DetectionGeometry | null | undefined, fallbackLat?: number, fallbackLon?: number) {
  if (
    typeof fallbackLat === 'number' &&
    typeof fallbackLon === 'number' &&
    Number.isFinite(fallbackLat) &&
    Number.isFinite(fallbackLon)
  ) {
    return { lat: fallbackLat, lon: fallbackLon };
  }

  const points = collectGeometryPoints(geometry);

  if (points.length === 0) {
    return { lat: 0, lon: 0 };
  }

  const total = points.reduce(
    (acc, [lon, lat]) => ({ lon: acc.lon + lon, lat: acc.lat + lat }),
    { lon: 0, lat: 0 },
  );

  return {
    lat: total.lat / points.length,
    lon: total.lon / points.length,
  };
}

function isGeoJSONFeatureCollection(value: unknown): value is GeoJSONFeatureCollection {
  const candidate = value as Partial<GeoJSONFeatureCollection> | null;

  return Boolean(
    candidate &&
      typeof candidate === 'object' &&
      candidate.type === 'FeatureCollection' &&
      Array.isArray(candidate.features),
  );
}

function normalizeDetection(raw: Record<string, unknown>): DetectionSummary {
  const geometry = (raw.geometry as DetectionGeometry | null | undefined) ?? null;
  const classType = normalizeClassType(raw.class_type ?? raw.classType ?? raw.type ?? raw.class);
  const score = normalizeScore(raw.score);
  const detectedAt = String(raw.detected_at ?? raw.detectedAt ?? raw.lastDetectionAt ?? new Date().toISOString());
  const centroidRaw = raw.centroid as { lat?: unknown; lon?: unknown; lng?: unknown } | undefined;
  const centroid = getCentroid(
    geometry,
    centroidRaw ? Number(centroidRaw.lat) : undefined,
    centroidRaw ? Number(centroidRaw.lon ?? centroidRaw.lng) : undefined,
  );

  return {
    id: String(raw.id ?? crypto.randomUUID()),
    flightId: String(raw.flightId ?? raw.flight_id ?? 'unknown-flight'),
    classType,
    type: classType,
    status: (raw.status as DetectionSummary['status']) ?? 'active',
    score,
    severity: normalizeSeverity(raw.severity, score),
    title: raw.title ? String(raw.title) : null,
    description: raw.description ? String(raw.description) : null,
    detectedAt,
    lastDetectionAt: String(raw.last_detection_at ?? raw.lastDetectionAt ?? detectedAt),
    imagePath: raw.image_path ? String(raw.image_path) : raw.imagePath ? String(raw.imagePath) : null,
    centroid,
    geometry,
    stats: {
      commentsCount: Number((raw.stats as { commentsCount?: number } | undefined)?.commentsCount ?? raw.commentsCount ?? 0),
      eventsCount: Number((raw.stats as { eventsCount?: number } | undefined)?.eventsCount ?? raw.eventsCount ?? 0),
    },
  };
}

function normalizeGeoJSONFeature(feature: GeoJSONFeature): DetectionSummary {
  return normalizeDetection({
    id: feature.id,
    geometry: feature.geometry,
    ...(feature.properties ?? {}),
  });
}

function applyClientSideFilters(items: DetectionSummary[], payload: DetectionSearchRequest) {
  return items.filter((item) => {
    if (payload.classes.length > 0 && !payload.classes.includes(item.classType)) {
      return false;
    }

    if (payload.minScore !== undefined && item.score < payload.minScore) {
      return false;
    }

    if (payload.maxScore !== undefined && item.score > payload.maxScore) {
      return false;
    }

    if (payload.period?.from && Date.parse(item.detectedAt) < Date.parse(payload.period.from)) {
      return false;
    }

    if (payload.period?.to && Date.parse(item.detectedAt) > Date.parse(payload.period.to)) {
      return false;
    }

    return true;
  });
}

export async function searchDetections(
  payload: DetectionSearchRequest,
): Promise<DetectionSearchResponse> {
  if (USE_MOCKS) {
    return mockSearchDetections(payload);
  }

  const response = await authFetch(resolveApiUrl(QUERY_ENDPOINT), {
    method: 'POST',
    headers: getJsonHeaders(),
    body: JSON.stringify(buildBackendPayload(payload)),
  });

  if (!response.ok) {
    throw new Error(`Search failed with status ${response.status}`);
  }

  const json = await response.json() as Record<string, unknown>;
  const rawData = isGeoJSONFeatureCollection(json)
    ? json.features.map(normalizeGeoJSONFeature)
    : Array.isArray(json.data)
      ? json.data.map((item) => normalizeDetection(item as Record<string, unknown>))
      : Array.isArray(json.items)
        ? json.items.map((item) => normalizeDetection(item as Record<string, unknown>))
        : [];
  const data = applyClientSideFilters(rawData, payload);

  return {
    data,
    meta: {
      nextCursor: typeof (json.meta as { nextCursor?: string } | undefined)?.nextCursor === 'string'
        ? (json.meta as { nextCursor?: string }).nextCursor ?? null
        : null,
      count: data.length,
    },
  };
}

async function mockSearchDetections(
  payload: DetectionSearchRequest,
): Promise<DetectionSearchResponse> {
  const result = applyClientSideFilters([...MOCK_DETECTIONS], payload)
    .sort((left, right) => Date.parse(right.detectedAt) - Date.parse(left.detectedAt))
    .slice(0, payload.limit ?? 500);

  return {
    data: result,
    meta: {
      nextCursor: null,
      count: result.length,
    },
  };
}
