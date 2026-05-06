const ACCESS_TOKEN_STORAGE_KEY = "forestmap.access.token";

let accessToken: string | null = null;

function canUseSessionStorage() {
  return typeof window !== 'undefined' && typeof window.sessionStorage !== 'undefined';
}

function readStoredAccessToken() {
  if (!canUseSessionStorage()) {
    return null;
  }

  try {
    return window.sessionStorage.getItem(ACCESS_TOKEN_STORAGE_KEY);
  } catch {
    return null;
  }
}

accessToken = readStoredAccessToken();

export function setAccessToken(token: string | null) {
  accessToken = token;

  if (!canUseSessionStorage()) {
    return;
  }

  try {
    if (token) {
      window.sessionStorage.setItem(ACCESS_TOKEN_STORAGE_KEY, token);
    } else {
      window.sessionStorage.removeItem(ACCESS_TOKEN_STORAGE_KEY);
    }
  } catch {
    // ignore storage errors
  }
}

export function getAccessToken() {
  if (accessToken) {
    return accessToken;
  }

  accessToken = readStoredAccessToken();
  return accessToken;
}

export function clearAccessToken() {
  setAccessToken(null);
}
