import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import '../../App.css';

import {
  addIcon,
  bugsIcon,
  distanceIcon,
  fireIcon,
  layersIcon,
  refreshIcon,
  screenshotIcon,
  sciIcon,
  shareIcon,
  tutorIcon,
} from '../../assets/icons';
import type {
  BBox,
  DetectionSummary,
  DetectionType,
} from '../../entities/detection/types';
import { searchDetections } from '../../features/detections-search/api';
import { MapView } from '../../widgets/map-view/MapView';
import { InfoPanel } from '../../widgets/info-panel/InfoPanel';

type ZoomCommand =
  | { id: number; direction: 'in' | 'out' }
  | null;

type FocusRequest =
  | {
    id: number;
    centroid: { lat: number; lon: number };
    geometry: DetectionSummary['geometry'] | null | undefined;
  }
  | null;

type MapLayerMode = 'osm' | 'satellite';

const SEARCH_DEBOUNCE_MS = 300;
const DEFAULT_SCORE_MIN = 0;
const DEFAULT_SCORE_MAX = 1;
const DEFAULT_SELECTED_TYPES: DetectionType[] = ['fire', 'infection', 'logging'];
const SCORE_STEP = 0.01;

function toDateInputValue(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function addDays(date: Date, days: number) {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

const DEFAULT_DATE_TO = toDateInputValue(new Date());
const DEFAULT_DATE_FROM = toDateInputValue(addDays(new Date(), -30));

function toStartOfDayIso(value: string) {
  return `${value}T00:00:00Z`;
}

function toEndOfDayIso(value: string) {
  return `${value}T23:59:59Z`;
}

function cycleLayer(layer: MapLayerMode): MapLayerMode {
  return layer === 'osm' ? 'satellite' : 'osm';
}

function formatScore(value: number) {
  return value.toFixed(2);
}

function clampScore(value: number) {
  return Math.min(DEFAULT_SCORE_MAX, Math.max(DEFAULT_SCORE_MIN, Number(value.toFixed(2))));
}

export function MapPage() {
  const [items, setItems] = useState<DetectionSummary[]>([]);
  const [scoreMin, setScoreMin] = useState(DEFAULT_SCORE_MIN);
  const [scoreMax, setScoreMax] = useState(DEFAULT_SCORE_MAX);
  const [dateFrom, setDateFrom] = useState(DEFAULT_DATE_FROM);
  const [dateTo, setDateTo] = useState(DEFAULT_DATE_TO);
  const [selectedTypes, setSelectedTypes] = useState<DetectionType[]>(DEFAULT_SELECTED_TYPES);
  const [mapLayer, setMapLayer] = useState<MapLayerMode>('osm');

  const [coords, setCoords] = useState({ lat: 60.1234, lng: 30.5678 });
  const [selectedDetectionId, setSelectedDetectionId] = useState<string | null>(null);
  const [focusRequest, setFocusRequest] = useState<FocusRequest>(null);
  const [zoomCommand, setZoomCommand] = useState<ZoomCommand>(null);
  const [bbox, setBbox] = useState<BBox>({
    minLon: 30.1,
    minLat: 60.0,
    maxLon: 30.9,
    maxLat: 60.5,
  });

  const [isLoading, setIsLoading] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);

  const latestRequestIdRef = useRef(0);

  const scoreMinPercent = scoreMin * 100;
  const scoreMaxPercent = scoreMax * 100;

  const isFiltersDirty = useMemo(() => {
    const typesChanged =
      selectedTypes.length !== DEFAULT_SELECTED_TYPES.length ||
      DEFAULT_SELECTED_TYPES.some((type) => !selectedTypes.includes(type));

    return (
      scoreMin !== DEFAULT_SCORE_MIN ||
      scoreMax !== DEFAULT_SCORE_MAX ||
      dateFrom !== DEFAULT_DATE_FROM ||
      dateTo !== DEFAULT_DATE_TO ||
      typesChanged
    );
  }, [dateFrom, dateTo, scoreMin, scoreMax, selectedTypes]);

  const loadDetections = useCallback(
    async (currentBbox: BBox = bbox) => {
      const requestId = ++latestRequestIdRef.current;
      setIsLoading(true);
      setSearchError(null);

      try {
        const result = await searchDetections({
          classes: selectedTypes,
          bbox: currentBbox,
          geom: 'auto',
          minScore: scoreMin,
          maxScore: scoreMax,
          period: {
            from: dateFrom ? toStartOfDayIso(dateFrom) : undefined,
            to: dateTo ? toEndOfDayIso(dateTo) : undefined,
          },
          limit: 500,
        });

        if (requestId !== latestRequestIdRef.current) {
          return;
        }

        setItems(result.data);
        setSelectedDetectionId((prev) => (
          prev && result.data.some((item) => item.id === prev) ? prev : null
        ));
      } catch (error) {
        if (requestId !== latestRequestIdRef.current) {
          return;
        }

        setSearchError(
          error instanceof Error ? error.message : 'Не удалось выполнить поиск детекций',
        );
        setItems([]);
      } finally {
        if (requestId === latestRequestIdRef.current) {
          setIsLoading(false);
        }
      }
    },
    [bbox, dateFrom, dateTo, scoreMax, scoreMin, selectedTypes],
  );

  useEffect(() => {
    const timeoutId = window.setTimeout(() => {
      void loadDetections(bbox);
    }, SEARCH_DEBOUNCE_MS);

    return () => {
      window.clearTimeout(timeoutId);
    };
  }, [bbox, loadDetections]);

  const selectedDetection = useMemo(
    () => items.find((item) => item.id === selectedDetectionId) ?? null,
    [items, selectedDetectionId],
  );

  const handleBoundsChange = useCallback((nextBbox: BBox) => {
    setBbox((prev) => {
      const isSame =
        prev.minLon === nextBbox.minLon &&
        prev.minLat === nextBbox.minLat &&
        prev.maxLon === nextBbox.maxLon &&
        prev.maxLat === nextBbox.maxLat;

      return isSame ? prev : nextBbox;
    });
  }, []);

  const handleMouseCoordsChange = useCallback((nextCoords: { lat: number; lng: number }) => {
    setCoords(nextCoords);
  }, []);

  const handleSelectDetection = useCallback(
    (id: string) => {
      if (selectedDetectionId === id) {
        setSelectedDetectionId(null);
        return;
      }

      const item = items.find((detection) => detection.id === id);
      setSelectedDetectionId(id);

      if (item) {
        setFocusRequest({
          id: Date.now(),
          centroid: item.centroid,
          geometry: item.geometry,
        });
      }
    },
    [items, selectedDetectionId],
  );

  const handleCloseSelection = useCallback(() => {
    setSelectedDetectionId(null);
  }, []);

  const toggleType = useCallback((type: DetectionType) => {
    setSelectedTypes((prev) =>
      prev.includes(type)
        ? prev.filter((item) => item !== type)
        : [...prev, type],
    );
  }, []);

  const triggerZoom = useCallback((direction: 'in' | 'out') => {
    setZoomCommand({ id: Date.now(), direction });
  }, []);

  const retrySearch = useCallback(() => {
    void loadDetections(bbox);
  }, [bbox, loadDetections]);

  const resetFilters = useCallback(() => {
    setScoreMin(DEFAULT_SCORE_MIN);
    setScoreMax(DEFAULT_SCORE_MAX);
    setDateFrom(DEFAULT_DATE_FROM);
    setDateTo(DEFAULT_DATE_TO);
    setSelectedTypes(DEFAULT_SELECTED_TYPES);
  }, []);

  const cycleMapLayer = useCallback(() => {
    setMapLayer((prev) => cycleLayer(prev));
  }, []);

  const handleScoreMinChange = useCallback((value: number) => {
    const nextValue = clampScore(value);
    setScoreMin(Math.min(nextValue, scoreMax));
  }, [scoreMax]);

  const handleScoreMaxChange = useCallback((value: number) => {
    const nextValue = clampScore(value);
    setScoreMax(Math.max(nextValue, scoreMin));
  }, [scoreMin]);

  return (
    <div className="map-page">
      <div className="map-layout">
        <aside className="sidebar">
          <div className="sidebar-static">
            <div className="sidebar-section">
              <div className="sidebar-label-row">
                <label>Обновить данные</label>
                <button
                  className="refresh-btn-active"
                  type="button"
                  onClick={retrySearch}
                  disabled={isLoading}
                  aria-busy={isLoading}
                >
                  <img src={refreshIcon} className="sidebar-icon-img" alt="Обновить данные" />
                </button>
              </div>
              <select className="ui-element sidebar-select" defaultValue="sev-zap">
                <option value="sev-zap">СЕВ-ЗАП Лесничество</option>
              </select>
            </div>

            <div className="sidebar-section icons-row-container" aria-label="Типы аномалий">
              <button
                className={`sidebar-icon-btn ${selectedTypes.includes('fire') ? 'sidebar-icon-btn-active' : ''}`}
                type="button"
                onClick={() => toggleType('fire')}
              >
                <img src={fireIcon} className="sidebar-icon-img" alt="" aria-hidden="true" />
                <span className="label-text">Пожары</span>
              </button>

              <button
                className={`sidebar-icon-btn ${selectedTypes.includes('infection') ? 'sidebar-icon-btn-active' : ''}`}
                type="button"
                onClick={() => toggleType('infection')}
              >
                <img src={bugsIcon} className="sidebar-icon-img" alt="" aria-hidden="true" />
                <span className="label-text">Заражения</span>
              </button>

              <button
                className={`sidebar-icon-btn ${selectedTypes.includes('logging') ? 'sidebar-icon-btn-active' : ''}`}
                type="button"
                onClick={() => toggleType('logging')}
              >
                <img src={sciIcon} className="sidebar-icon-img" alt="" aria-hidden="true" />
                <span className="label-text">Вырубки</span>
              </button>
            </div>

            <div className="sidebar-section">
              <label>Score: {formatScore(scoreMin)} — {formatScore(scoreMax)}</label>
              <div className="double-range-slider score-range-slider">
                <div className="slider-track-base" />
                <div
                  className="slider-track-fill"
                  style={{
                    left: `${scoreMinPercent}%`,
                    right: `${100 - scoreMaxPercent}%`,
                  }}
                />
                <input
                  aria-label="Минимальный score"
                  type="range"
                  min={DEFAULT_SCORE_MIN}
                  max={DEFAULT_SCORE_MAX}
                  step={SCORE_STEP}
                  value={scoreMin}
                  onChange={(event) => handleScoreMinChange(Number(event.target.value))}
                />
                <input
                  aria-label="Максимальный score"
                  type="range"
                  min={DEFAULT_SCORE_MIN}
                  max={DEFAULT_SCORE_MAX}
                  step={SCORE_STEP}
                  value={scoreMax}
                  onChange={(event) => handleScoreMaxChange(Number(event.target.value))}
                />
              </div>
              <div className="score-range-values">
                <span>min {formatScore(scoreMin)}</span>
                <span>max {formatScore(scoreMax)}</span>
              </div>
            </div>

            <div className="sidebar-section">
              <label>Период детекции</label>
              <div className="date-range-group">
                <input
                  type="date"
                  className="ui-element"
                  value={dateFrom}
                  onChange={(event) => setDateFrom(event.target.value)}
                />
                <span className="date-separator">—</span>
                <input
                  type="date"
                  className="ui-element"
                  value={dateTo}
                  onChange={(event) => setDateTo(event.target.value)}
                />
              </div>
            </div>

            <div className="sidebar-actions sidebar-actions--split">
              <div className="sidebar-actions">
                <button
                  type="button"
                  className="sidebar-secondary-btn"
                  onClick={resetFilters}
                  disabled={!isFiltersDirty}
                >
                  Сбросить
                </button>
              </div>
            </div>
          </div>

          <div className="sidebar-scroll-header">
            <span>Последние детекции ({items.length})</span>
            <button className="refresh-btn-active" type="button" aria-label="Добавить детекцию">
              <img src={addIcon} className="sidebar-icon-img" alt="" aria-hidden="true" />
            </button>
          </div>

          <div className="sidebar-scroll">
            {isLoading && (
              <div className="sidebar-state">
                <div className="sidebar-state__title">Идет поиск…</div>
                <div className="sidebar-state__text">
                  Обновляем список детекций по текущим фильтрам и области карты.
                </div>
              </div>
            )}

            {!isLoading && searchError && (
              <div className="sidebar-state sidebar-state--error">
                <div className="sidebar-state__title">Ошибка поиска</div>
                <div className="sidebar-state__text">{searchError}</div>
                <button className="sidebar-state__action" type="button" onClick={retrySearch}>
                  Повторить
                </button>
              </div>
            )}

            {!isLoading && !searchError && items.length === 0 && (
              <div className="sidebar-state">
                <div className="sidebar-state__title">Ничего не найдено</div>
                <div className="sidebar-state__text">
                  Попробуй изменить фильтры, период или переместить карту.
                </div>
              </div>
            )}

            {!isLoading && !searchError && items.map((item) => (
              <div
                key={item.id}
                className={`scroll-item ${selectedDetectionId === item.id ? 'scroll-item-selected' : ''}`}
                onClick={() => handleSelectDetection(item.id)}
              >
                <div className="scroll-item__title">{item.title ?? item.id}</div>
                <span className="bottom-label">
                  {new Date(item.detectedAt).toLocaleString()} / {item.classType} / score {formatScore(item.score)}
                </span>
              </div>
            ))}
          </div>
        </aside>

        <main className="content">
          <div className="coords-overlay">
            <span className="coord-val">{coords.lat.toFixed(6)} N</span>
            <span className="coord-sep">|</span>
            <span className="coord-val">{coords.lng.toFixed(6)} E</span>
          </div>

          <div className="zoom-controls">
            <button className="zoom-btn" type="button" onClick={() => triggerZoom('in')}>+</button>
            <button className="zoom-btn" type="button" onClick={() => triggerZoom('out')}>−</button>
          </div>

          <div className="map-layer-chip">
            Слой: {mapLayer === 'osm' ? 'OSM' : 'Спутник'}
          </div>

          {isLoading && (
            <div className="map-search-state map-search-state--loading">
              Идет поиск…
            </div>
          )}

          {!isLoading && searchError && (
            <div className="map-search-state map-search-state--error">
              Ошибка поиска
            </div>
          )}

          {!isLoading && !searchError && items.length === 0 && (
            <div className="map-search-state">
              По текущим фильтрам ничего не найдено
            </div>
          )}

          <MapView
            items={items}
            selectedDetectionId={selectedDetectionId}
            focusRequest={focusRequest}
            zoomCommand={zoomCommand}
            mapLayer={mapLayer}
            onSelectDetection={handleSelectDetection}
            onBoundsChange={handleBoundsChange}
            onMouseCoordsChange={handleMouseCoordsChange}
          />

          <InfoPanel
            item={selectedDetection}
            items={items}
            onCloseSelection={handleCloseSelection}
          />
        </main>
      </div>

      <div className="bottom-bar">
        <button className="bottom-item bottom-item--button" type="button">
          <span className="bottom-icon"><img src={distanceIcon} className="bottom-icon" alt="Расстояние" /></span>
          <span className="bottom-label">Расстояние</span>
        </button>
        <button className="bottom-item bottom-item--button" type="button">
          <span className="bottom-icon"><img src={addIcon} className="bottom-icon" alt="Добавить" /></span>
          <span className="bottom-label">Добавить</span>
        </button>
        <button className="bottom-item bottom-item--button" type="button" onClick={cycleMapLayer}>
          <span className="bottom-icon"><img src={layersIcon} className="bottom-icon" alt="Слои" /></span>
          <span className="bottom-label">{mapLayer === 'osm' ? 'Слои: OSM' : 'Слои: Спутник'}</span>
        </button>
        <button className="bottom-item bottom-item--button" type="button">
          <span className="bottom-icon"><img src={shareIcon} className="bottom-icon" alt="Поделиться" /></span>
          <span className="bottom-label">Поделиться</span>
        </button>
        <button className="bottom-item bottom-item--button" type="button">
          <span className="bottom-icon"><img src={screenshotIcon} className="bottom-icon" alt="Снимок" /></span>
          <span className="bottom-label">Снимок</span>
        </button>
        <button className="bottom-item bottom-item--button" type="button">
          <span className="bottom-icon"><img src={tutorIcon} className="bottom-icon" alt="Справка" /></span>
          <span className="bottom-label">Справка</span>
        </button>
      </div>
    </div>
  );
}
