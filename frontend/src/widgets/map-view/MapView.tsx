import { useEffect } from 'react';
import {
  CircleMarker,
  MapContainer,
  Popup,
  TileLayer,
  useMap,
  useMapEvents,
} from 'react-leaflet';
import type { LatLngBounds } from 'leaflet';
import 'leaflet/dist/leaflet.css';

type BBox = {
  minLon: number;
  minLat: number;
  maxLon: number;
  maxLat: number;
};

type DetectionItem = {
  id: string;
  type: 'fire' | 'infection' | 'logging';
  status: 'active' | 'resolved' | 'archived';
  score: number;
  title?: string | null;
  centroid: {
    lat: number;
    lon: number;
  };
};

type Props = {
  items?: DetectionItem[];
  selectedDetectionId?: string | null;
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

function MapEvents({
  onBoundsChange,
  onMouseCoordsChange,
}: Omit<Props, 'items' | 'selectedDetectionId' | 'onSelectDetection'>) {
  const map = useMap();

  useEffect(() => {
    onBoundsChange(boundsToBBox(map.getBounds()));
  }, [map]);

  useMapEvents({
    moveend() {
      onBoundsChange(boundsToBBox(map.getBounds()));
    },
    mousemove(event) {
      onMouseCoordsChange({
        lat: event.latlng.lat,
        lng: event.latlng.lng,
      });
    },
  });

  return null;
}

function SelectionController({
  items,
  selectedDetectionId,
}: {
  items: DetectionItem[];
  selectedDetectionId: string | null;
}) {
  const map = useMap();

  useEffect(() => {
    console.log('selectedDetectionId changed:', selectedDetectionId);

    if (!selectedDetectionId) {
      return;
    }

    const selectedItem = items.find((item) => item.id === selectedDetectionId);
    console.log('selectedItem:', selectedItem);

    if (!selectedItem) {
      return;
    }

    map.setView([selectedItem.centroid.lat, selectedItem.centroid.lon], 14);
  }, [map, items, selectedDetectionId]);

  return null;
}

function getMarkerColor(type: DetectionItem['type']) {
  switch (type) {
    case 'fire':
      return '#ef4444';
    case 'infection':
      return '#eab308';
    case 'logging':
      return '#22c55e';
    default:
      return '#3b82f6';
  }
}

export function MapView({
  items = [],
  selectedDetectionId = null,
  onSelectDetection,
  onBoundsChange,
  onMouseCoordsChange,
}: Props) {
  return (
    <MapContainer
      center={[60.1234, 30.5678]}
      zoom={10}
      className="leaflet-map"
      zoomControl={false}
    >
      <TileLayer
        attribution="&copy; OpenStreetMap contributors"
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />

      <MapEvents
        onBoundsChange={onBoundsChange}
        onMouseCoordsChange={onMouseCoordsChange}
      />

      <SelectionController
        items={items}
        selectedDetectionId={selectedDetectionId}
      />

      {items.map((item) => {
        const isSelected = selectedDetectionId === item.id;
        const baseColor = getMarkerColor(item.type);

        return (
          <CircleMarker
            key={item.id}
            center={[item.centroid.lat, item.centroid.lon]}
            radius={isSelected ? 12 : 8}
            eventHandlers={{
              click: () => onSelectDetection?.(item.id),
            }}
            pathOptions={{
              color: isSelected ? '#ffffff' : baseColor,
              fillColor: baseColor,
              weight: isSelected ? 3 : 2,
              fillOpacity: isSelected ? 0.95 : 0.7,
            }}
          >
            <Popup>
              <div>
                <strong>{item.title ?? item.id}</strong>
                <div>Тип: {item.type}</div>
                <div>Статус: {item.status}</div>
                <div>Score: {item.score}</div>
              </div>
            </Popup>
          </CircleMarker>
        );
      })}
    </MapContainer>
  );
}