import type {
  DetectionSearchRequest,
  DetectionSearchResponse,
} from '../../entities/detection/types';

const USE_MOCKS = true;

export async function searchDetections(
  _payload: DetectionSearchRequest,
): Promise<DetectionSearchResponse> {
  if (USE_MOCKS) {
    return mockSearchDetections();
  }

  const response = await fetch('/api/v1/detections/search', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      // позже добавим Authorization
    },
    body: JSON.stringify(_payload),
  });

  if (!response.ok) {
    throw new Error(`Search failed with status ${response.status}`);
  }

  return response.json();
}

async function mockSearchDetections(): Promise<DetectionSearchResponse> {
  return {
    data: [
      {
        id: 'det-1',
        flightId: 'flight-1',
        type: 'fire',
        status: 'active',
        score: 8,
        title: 'Пожар 1',
        description: 'Моковый polygon',
        lastDetectionAt: '2026-04-19T12:30:00Z',
        centroid: {
          lat: 60.1234,
          lon: 30.5678,
        },
        geometry: {
          type: 'Polygon',
          coordinates: [[
            [30.55, 60.12],
            [30.58, 60.12],
            [30.58, 60.14],
            [30.55, 60.14],
            [30.55, 60.12],
          ]],
        },
        stats: {
          commentsCount: 2,
          eventsCount: 5,
        },
      },
      {
        id: 'det-2',
        flightId: 'flight-1',
        type: 'logging',
        status: 'active',
        score: 5,
        title: 'Вырубка 1',
        description: 'Моковый multipolygon',
        lastDetectionAt: '2026-04-19T12:30:00Z',
        centroid: {
          lat: 60.30,
          lon: 30.90,
        },
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
        stats: {
          commentsCount: 1,
          eventsCount: 3,
        },
      },
      {
        id: 'det-3',
        flightId: 'flight-1',
        type: 'infection',
        status: 'active',
        score: 4,
        title: 'Заражение 1',
        description: 'Без geometry, только centroid',
        lastDetectionAt: '2026-04-19T12:30:00Z',
        centroid: {
          lat: 59.95,
          lon: 30.20,
        },
        geometry: null,
        stats: {
          commentsCount: 0,
          eventsCount: 2,
        },
      },
    ],
    meta: {
      nextCursor: null,
      count: 3,
    },
  };
}