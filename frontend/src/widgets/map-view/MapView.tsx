import { useEffect, useMemo } from 'react';
import {
  CircleMarker,
  MapContainer,
  Polygon,
  Popup,
  TileLayer,
  useMap,
  useMapEvents,
} from 'react-leaflet';
import type { LatLngBounds, LatLngTuple, LeafletMouseEvent } from 'leaflet';
import type { BBox, DetectionClassType, DetectionGeometry, DetectionSummary } from '../../entities/detection/types';
import 'leaflet/dist/leaflet.css';

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

type Props = {
  items?: DetectionSummary[];
  selectedDetectionId?: string | null;
  focusRequest?: FocusRequest;
  zoomCommand?: ZoomCommand;
  mapLayer: MapLayerMode;
  onSelectDetection?: (id: string) => void;
  onBoundsChange: (bbox: BBox) => void;
  onMouseCoordsChange: (coords: { lat: number; lng: number }) => void;
};

function boundsToBBox(bounds: LatLngBounds): BBox {
  const southWest = bounds.getSouthWest();
  const northEast = bounds.getNorthEast();

  return {
    minLon: southWest.lng,
    minLat: southWest.lat,
    maxLon: northEast.lng,
    maxLat: northEast.lat,
  };
}

function MapEvents({ onBoundsChange, onMouseCoordsChange }: Pick<Props, 'onBoundsChange' | 'onMouseCoordsChange'>) {
  const map = useMap();

  useEffect(() => {
    onBoundsChange(boundsToBBox(map.getBounds()));
  }, [map, onBoundsChange]);

  useMapEvents({
    moveend() {
      onBoundsChange(boundsToBBox(map.getBounds()));
    },
    mousemove(event: LeafletMouseEvent) {
      onMouseCoordsChange({
        lat: event.latlng.lat,
        lng: event.latlng.lng,
      });
    },
  });

  return null;
}

function FocusController({ focusRequest }: { focusRequest: FocusRequest }) {
  const map = useMap();

  useEffect(() => {
    if (!focusRequest) {
      return;
    }

    const boundsPoints = getBoundsPointsFromGeometry(focusRequest.geometry);

    if (boundsPoints && boundsPoints.length > 1) {
      map.fitBounds(boundsPoints, {
        padding: [40, 40],
        maxZoom: 15,
      });
      return;
    }

    map.flyTo([focusRequest.centroid.lat, focusRequest.centroid.lon], 13, {
      duration: 0.8,
    });
  }, [focusRequest, map]);

  return null;
}

function ZoomController({ zoomCommand }: { zoomCommand: ZoomCommand }) {
  const map = useMap();

  useEffect(() => {
    if (!zoomCommand) {
      return;
    }

    if (zoomCommand.direction === 'in') {
      map.zoomIn();
      return;
    }

    map.zoomOut();
  }, [map, zoomCommand]);

  return null;
}

function getGeometryColor(classType: DetectionClassType) {
  switch (classType) {
    case 'fire':
      return '#ef4444';
    case 'infection':
      return '#f59e0b';
    case 'logging':
      return '#0f7a3a';
    default:
      return '#0f7a3a';
  }
}

function getLayerConfig(mapLayer: MapLayerMode) {
  if (mapLayer === 'satellite') {
    return {
      url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      attribution: 'Tiles © Esri',
      label: 'Esri World Imagery',
    };
  }

  return {
    url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
    label: 'OpenStreetMap',
  };
}

function toLatLngTuple(position: number[]): LatLngTuple {
  return [position[1], position[0]];
}

function polygonToPositions(coordinates: number[][][] | undefined): LatLngTuple[] {
  const outerRing = coordinates?.[0] ?? [];
  return outerRing.map(toLatLngTuple);
}

function multiPolygonToPositions(coordinates: number[][][][] | undefined): LatLngTuple[][] {
  const polygons = coordinates ?? [];

  return polygons.map((polygon) => {
    const outerRing = polygon?.[0] ?? [];
    return outerRing.map(toLatLngTuple);
  });
}

function getBoundsPointsFromGeometry(geometry: DetectionGeometry | null | undefined): LatLngTuple[] | null {
  if (!geometry) {
    return null;
  }

  if (geometry.type === 'Point') {
    return [[geometry.coordinates[1], geometry.coordinates[0]]];
  }

  if (geometry.type === 'Polygon') {
    const positions = polygonToPositions(geometry.coordinates);
    return positions.length > 0 ? positions : null;
  }

  if (geometry.type === 'MultiPolygon') {
    const polygons = multiPolygonToPositions(geometry.coordinates);
    const flat = polygons.flat();
    return flat.length > 0 ? flat : null;
  }

  return null;
}

function formatScore(value: number) {
  return value.toFixed(2);
}

function MapPopupContent({ item }: { item: DetectionSummary }) {
  return (
    <div className="map-popup">
      <div className="map-popup__title">{item.title ?? item.id}</div>
      <div className="map-popup__row"><span>class_type</span><strong>{item.classType}</strong></div>
      <div className="map-popup__row"><span>detected_at</span><strong>{new Date(item.detectedAt).toLocaleString()}</strong></div>
      <div className="map-popup__row"><span>score</span><strong>{formatScore(item.score)}</strong></div>
      <div className="map-popup__row"><span>severity</span><strong>{item.severity}</strong></div>
      <div className="map-popup__row"><span>image_path</span><strong>{item.imagePath ? <a href={item.imagePath} target="_blank" rel="noreferrer">open</a> : '—'}</strong></div>
    </div>
  );
}

function DetectionLayer({
  item,
  selectedDetectionId,
  onSelectDetection,
}: {
  item: DetectionSummary;
  selectedDetectionId: string | null;
  onSelectDetection?: (id: string) => void;
}) {
  const isSelected = selectedDetectionId === item.id;
  const color = getGeometryColor(item.classType);

  if (!item.geometry || item.geometry.type === 'Point') {
    const point = item.geometry?.type === 'Point'
      ? { lat: item.geometry.coordinates[1], lon: item.geometry.coordinates[0] }
      : item.centroid;

    return (
      <CircleMarker
        key={item.id}
        center={[point.lat, point.lon]}
        radius={isSelected ? 9 : 7}
        eventHandlers={{ click: () => onSelectDetection?.(item.id) }}
        pathOptions={{
          color: isSelected ? '#ffffff' : color,
          weight: isSelected ? 3 : 2,
          fillColor: color,
          fillOpacity: 0.92,
        }}
      >
        <Popup>
          <MapPopupContent item={item} />
        </Popup>
      </CircleMarker>
    );
  }

  if (item.geometry.type === 'Polygon') {
    const positions = polygonToPositions(item.geometry.coordinates);

    if (positions.length === 0) {
      return null;
    }

    return (
      <Polygon
        key={item.id}
        positions={positions}
        eventHandlers={{ click: () => onSelectDetection?.(item.id) }}
        pathOptions={{
          color: isSelected ? '#ffffff' : color,
          weight: isSelected ? 3 : 2,
          fillColor: color,
          fillOpacity: item.classType === 'logging' ? 0.32 : 0.24,
        }}
      >
        <Popup>
          <MapPopupContent item={item} />
        </Popup>
      </Polygon>
    );
  }

  const polygons = multiPolygonToPositions(item.geometry.coordinates);

  if (polygons.length === 0) {
    return null;
  }

  return (
    <>
      {polygons.map((positions, index) => (
        <Polygon
          key={`${item.id}-${index}`}
          positions={positions}
          eventHandlers={{ click: () => onSelectDetection?.(item.id) }}
          pathOptions={{
            color: isSelected ? '#ffffff' : color,
            weight: isSelected ? 3 : 2,
            fillColor: color,
            fillOpacity: item.classType === 'logging' ? 0.32 : 0.24,
          }}
        >
          {index === 0 ? (
            <Popup>
              <MapPopupContent item={item} />
            </Popup>
          ) : null}
        </Polygon>
      ))}
    </>
  );
}

export function MapView({
  items = [],
  selectedDetectionId = null,
  focusRequest = null,
  zoomCommand = null,
  mapLayer,
  onSelectDetection,
  onBoundsChange,
  onMouseCoordsChange,
}: Props) {
  const tileConfig = useMemo(() => getLayerConfig(mapLayer), [mapLayer]);

  return (
    <div className="map-view-shell">
      <MapContainer
        center={[60.1234, 30.5678]}
        zoom={10}
        className="leaflet-map"
        zoomControl={false}
        attributionControl={false}
      >
        <TileLayer attribution={tileConfig.attribution} url={tileConfig.url} />

        <MapEvents
          onBoundsChange={onBoundsChange}
          onMouseCoordsChange={onMouseCoordsChange}
        />

        <FocusController focusRequest={focusRequest} />
        <ZoomController zoomCommand={zoomCommand} />

        {items.map((item) => (
          <DetectionLayer
            key={item.id}
            item={item}
            selectedDetectionId={selectedDetectionId}
            onSelectDetection={onSelectDetection}
          />
        ))}
      </MapContainer>

      <div className="map-attribution">{tileConfig.label} | {tileConfig.attribution}</div>
    </div>
  );
}
