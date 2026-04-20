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
    data: Array.from({ length: 20 }, (_, index) => ({
      id: `det-${index + 1}`,
      flightId: 'flight-1',
      type: index % 3 === 0 ? 'fire' : index % 3 === 1 ? 'infection' : 'logging',
      status: 'active',
      score: (index % 10) + 1,
      title: `Детекция ${index + 1}`,
      description: 'Моковые данные для фронта',
      lastDetectionAt: '2026-04-19T12:30:00Z',
      centroid: {
        lat: 60.12 + index * 0.001,
        lon: 30.56 + index * 0.001,
      },
      geometry: null,
      stats: {
        commentsCount: index % 4,
        eventsCount: index % 6,
      },
    })),
    meta: {
      nextCursor: null,
      count: 20,
    },
  };
}