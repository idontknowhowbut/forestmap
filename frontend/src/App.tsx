import { useEffect, useState } from 'react';
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

// Хак для иконок Leaflet (в React они иногда ломаются без этого)
import icon from 'leaflet/dist/images/marker-icon.png';
import iconShadow from 'leaflet/dist/images/marker-shadow.png';

const DefaultIcon = L.icon({
    iconUrl: icon,
    shadowUrl: iconShadow,
    iconSize: [25, 41],
    iconAnchor: [12, 41],
});
L.Marker.prototype.options.icon = DefaultIcon;

// Типы данных (совпадают с твоим API)
type Feature = {
  type: "Feature";
  geometry: {
    type: "Point";
    coordinates: [number, number]; // GeoJSON: [Lon, Lat]
  };
  properties: {
    type: string;
    observed_at: string;
  };
};

type FeatureCollection = {
  type: "FeatureCollection";
  features: Feature[];
};

function App() {
  const [features, setFeatures] = useState<Feature[]>([]);

  // Загружаем данные при старте
  useEffect(() => {
    fetch('/api/v1/events')
      .then((res) => res.json())
      .then((data: FeatureCollection) => {
        setFeatures(data.features || []);
      })
      .catch((err) => console.error("Error loading events:", err));
  }, []);

  return (
    <MapContainer 
      center={[55.75, 37.61]} // Центр карты (Москва)
      zoom={5} 
      style={{ height: '100vh', width: '100%' }}
    >
      {/* Слой карты OSM */}
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />

      {/* Рисуем маркеры */}
      {features.map((f, idx) => {
        // GeoJSON хранит [Lon, Lat], а Leaflet хочет [Lat, Lon]. Переворачиваем!
        const [lon, lat] = f.geometry.coordinates;
        
        return (
          <Marker key={idx} position={[lat, lon]}>
            <Popup>
              <b>{f.properties.type}</b><br />
              {new Date(f.properties.observed_at).toLocaleString()}
            </Popup>
          </Marker>
        );
      })}
    </MapContainer>
  );
}

export default App;