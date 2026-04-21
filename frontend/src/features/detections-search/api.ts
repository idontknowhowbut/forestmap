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
          lat: 60.135,
          lon: 30.61,
        },
        geometry: {
          type: 'MultiPolygon',
          coordinates: [
            [[
              [30.60, 60.13],
              [30.62, 60.13],
              [30.62, 60.145],
              [30.60, 60.145],
              [30.60, 60.13],
            ]],
            [[
              [30.63, 60.135],
              [30.645, 60.135],
              [30.645, 60.15],
              [30.63, 60.15],
              [30.63, 60.135],
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
          lat: 60.11,
          lon: 30.53,
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