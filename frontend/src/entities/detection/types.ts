export type DetectionClassType = 'fire' | 'infection' | 'logging';
export type DetectionType = DetectionClassType;
export type DetectionStatus = 'active' | 'resolved' | 'archived';
export type DetectionSeverity = 'low' | 'medium' | 'high' | 'critical';
export type GeometryMode = 'auto' | 'point' | 'polygon';

export type BBox = {
  minLon: number;
  minLat: number;
  maxLon: number;
  maxLat: number;
};

export type GeoPoint = {
  lat: number;
  lon: number;
};

export type PointGeometry = {
  type: 'Point';
  coordinates: [number, number];
};

export type PolygonGeometry = {
  type: 'Polygon';
  coordinates: number[][][];
};

export type MultiPolygonGeometry = {
  type: 'MultiPolygon';
  coordinates: number[][][][];
};

export type DetectionGeometry = PointGeometry | PolygonGeometry | MultiPolygonGeometry;

export type GeoJSONFeature = {
  type: 'Feature';
  id?: string | number | null;
  geometry: DetectionGeometry | null;
  properties?: Record<string, unknown> | null;
};

export type GeoJSONFeatureCollection = {
  type: 'FeatureCollection';
  features: GeoJSONFeature[];
};

export type DetectionStats = {
  commentsCount: number;
  eventsCount: number;
};

export type DetectionSummary = {
  id: string;
  flightId: string;
  classType: DetectionClassType;
  type: DetectionType;
  status: DetectionStatus;
  score: number;
  severity: DetectionSeverity;
  title?: string | null;
  description?: string | null;
  detectedAt: string;
  lastDetectionAt: string;
  imagePath?: string | null;
  centroid: GeoPoint;
  geometry?: DetectionGeometry | null;
  stats: DetectionStats;
};

export type DetectionSearchRequest = {
  classes: DetectionType[];
  bbox?: BBox;
  minScore?: number;
  maxScore?: number;
  period?: {
    from?: string;
    to?: string;
  };
  geom?: GeometryMode;
  limit?: number;
};

export type DetectionSearchResponse = {
  data: DetectionSummary[];
  meta: {
    nextCursor: string | null;
    count: number;
  };
};
