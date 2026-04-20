export type DetectionType = 'fire' | 'infection' | 'logging';
export type DetectionStatus = 'active' | 'resolved' | 'archived';
export type GeometryMode = 'full' | 'simplified' | 'centroid';

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

export type PolygonGeometry = {
  type: 'Polygon';
  coordinates: number[][][];
};

export type MultiPolygonGeometry = {
  type: 'MultiPolygon';
  coordinates: number[][][][];
};

export type DetectionGeometry = PolygonGeometry | MultiPolygonGeometry;

export type DetectionStats = {
  commentsCount: number;
  eventsCount: number;
};

export type DetectionSummary = {
  id: string;
  flightId: string;
  type: DetectionType;
  status: DetectionStatus;
  score: number;
  title?: string | null;
  description?: string | null;
  lastDetectionAt: string;
  centroid: GeoPoint;
  geometry?: DetectionGeometry | null;
  stats: DetectionStats;
};

export type DetectionSearchRequest = {
  map: {
    bbox: BBox;
    geometryMode: GeometryMode;
  };
  filters?: {
    types?: DetectionType[];
    statuses?: DetectionStatus[];
    score?: {
      from?: number;
      to?: number;
    };
    period?: {
      from?: string;
      to?: string;
    };
    withComments?: boolean;
  };
  sort?: {
    field: 'lastDetectionAt' | 'score';
    direction: 'asc' | 'desc';
  };
  pagination: {
    limit: number;
    cursor?: string | null;
  };
};

export type DetectionSearchResponse = {
  data: DetectionSummary[];
  meta: {
    nextCursor: string | null;
    count: number;
  };
};