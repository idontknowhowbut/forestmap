import { getAccessToken } from './session';

export function buildAuthHeaders(headers?: HeadersInit): Headers {
  const result = new Headers(headers);
  const token = getAccessToken();

  if (token) {
    result.set('Authorization', `Bearer ${token}`);
  }

  return result;
}

export function authFetch(input: RequestInfo | URL, init: RequestInit = {}) {
  return fetch(input, {
    ...init,
    headers: buildAuthHeaders(init.headers),
  });
}
