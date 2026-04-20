import { useEffect, useState } from 'react';
import '../../App.css';

import distanceIcon from '../../distanceicon.png';
import addIcon from '../../addicon.png';
import layersIcon from '../../layersicon.png';
import shareIcon from '../../shareicon.png';
import screenshotIcon from '../../screenshoticon.png';
import tutorIcon from '../../tutoricon.png';
import themeIcon from '../../themeicon.png';
import exitIcon from '../../exiticon.png';
import bugsIcon from '../../bugsicon.png';
import sciIcon from '../../sciicon.png';
import fireIcon from '../../fireicon.png';
import refreshIcon from '../../refreshicon.png';
import adddetIcon from '../../adddetectionicon.png';

import { searchDetections } from '../../features/detections-search/api';
import type { DetectionSummary } from '../../entities/detection/types';

export function MapPage() {
  const [items, setItems] = useState<DetectionSummary[]>([]);
  const [rangeMin, setRangeMin] = useState(5);
  const [rangeMax, setRangeMax] = useState(10);
  const [coords, setCoords] = useState({ lat: 60.1234, lng: 30.5678 });

  useEffect(() => {
    void loadDetections();
  }, []);

  async function loadDetections() {
    const result = await searchDetections({
      map: {
        bbox: {
          minLon: 30.1,
          minLat: 60.0,
          maxLon: 30.9,
          maxLat: 60.5,
        },
        geometryMode: 'simplified',
      },
      filters: {
        statuses: ['active'],
        score: {
          from: rangeMin,
          to: rangeMax,
        },
      },
      sort: {
        field: 'lastDetectionAt',
        direction: 'desc',
      },
      pagination: {
        limit: 50,
        cursor: null,
      },
    });

    console.log('detections result', result);
    setItems(result.data);
  }

  const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    const lat = 60.5 - (y / rect.height) * 0.5;
    const lng = 30.1 + (x / rect.width) * 0.8;

    setCoords({ lat, lng });
  };

  return (
    <div className="app">
      <div className="top-bar">
        <div className="top-bar-left">
          <div className="top-nav-item">Карта</div>
          <div className="top-nav-item">Юзеры</div>
          <div className="top-nav-item">Журнал выгрузки</div>
          <div className="top-nav-item">Справочник вредителей</div>
        </div>

        <div className="top-bar-right">
          <div className="theme-toggle">
            <span><img src={themeIcon} className="bottom-icon" alt="" /></span>
          </div>
          <div className="user-profile">
            <span className="user-name">e_golovach|admin</span>
          </div>
          <button className="logout-btn">
            <span><img src={exitIcon} className="bottom-icon" alt="" /></span>
          </button>
        </div>
      </div>

      <div className="layout">
        <aside className="sidebar">
          <div className="sidebar-static">
            <div className="sidebar-section">
              <div className="sidebar-label-row">
                <label>Обновить данные</label>
                <button className="refresh-btn-active" onClick={() => void loadDetections()}>
                  <img src={refreshIcon} className="sidebar-icon-img" alt="" />
                </button>
              </div>
              <select className="ui-element sidebar-select">
                <option>СЕВ-ЗАП Лесничество</option>
              </select>
            </div>

            <div className="sidebar-section icons-row-container">
              <button className="sidebar-icon-btn">
                <img src={fireIcon} className="sidebar-icon-img" alt="" />
                <span className="label-text">Пожары</span>
              </button>
              <button className="sidebar-icon-btn">
                <img src={bugsIcon} className="sidebar-icon-img" alt="" />
                <span className="label-text">Заражения</span>
              </button>
              <button className="sidebar-icon-btn">
                <img src={sciIcon} className="sidebar-icon-img" alt="" />
                <span className="label-text">Вырубки</span>
              </button>
            </div>

            <div className="sidebar-section">
              <label>СТЕПЕНЬ УГРОЗЫ(SCORE): {rangeMin} — {rangeMax}</label>
              <div className="double-range-slider">
                <div className="slider-track-base"></div>
                <div
                  className="slider-track-fill"
                  style={{
                    left: `${(rangeMin / 10) * 100}%`,
                    right: `${100 - (rangeMax / 10) * 100}%`,
                  }}
                />
                <input
                  type="range"
                  min="0"
                  max="10"
                  value={rangeMin}
                  onChange={(e) => setRangeMin(Math.min(+e.target.value, rangeMax - 1))}
                />
                <input
                  type="range"
                  min="0"
                  max="10"
                  value={rangeMax}
                  onChange={(e) => setRangeMax(Math.max(+e.target.value, rangeMin + 1))}
                />
              </div>
            </div>

            <div className="sidebar-section">
              <label>Период детекции</label>
              <div className="date-range-group">
                <input type="date" className="ui-element" defaultValue="2026-04-01" />
                <span className="date-separator">—</span>
                <input type="date" className="ui-element" defaultValue="2026-04-17" />
              </div>
            </div>
          </div>

          <div className="sidebar-scroll-header">
            <span>Последние детекции ({items.length})</span>
            <button className="refresh-btn-active">
              <img src={adddetIcon} className="sidebar-icon-img" alt="" />
            </button>
          </div>

          <div className="sidebar-scroll">
            {items.map((item) => (
              <div key={item.id} className="scroll-item">
                {item.title ?? item.id}.{' '}
                <span className="bottom-label">
                  {new Date(item.lastDetectionAt).toLocaleString()} / score {item.score}
                </span>
              </div>
            ))}
          </div>
        </aside>

        <main className="content" onMouseMove={handleMouseMove}>
          <div className="coords-overlay">
            <span className="coord-val">{coords.lat.toFixed(6)} N</span>
            <span className="coord-sep">|</span>
            <span className="coord-val">{coords.lng.toFixed(6)} E</span>
          </div>

          <div className="zoom-controls">
            <button className="zoom-btn">+</button>
            <button className="zoom-btn">−</button>
          </div>

          <div className="map-placeholder">Карта будет здесь</div>
        </main>
      </div>

      <div className="bottom-bar">
        <div className="bottom-item">
          <span className="bottom-icon"><img src={distanceIcon} className="bottom-icon" alt="" /></span>
          <span className="bottom-label">Расстояние</span>
        </div>
        <div className="bottom-item">
          <span className="bottom-icon"><img src={addIcon} className="bottom-icon" alt="" /></span>
          <span className="bottom-label">Добавить</span>
        </div>
        <div className="bottom-item">
          <span className="bottom-icon"><img src={layersIcon} className="bottom-icon" alt="" /></span>
          <span className="bottom-label">Слои</span>
        </div>
        <div className="bottom-item">
          <span className="bottom-icon"><img src={shareIcon} className="bottom-icon" alt="" /></span>
          <span className="bottom-label">Поделиться</span>
        </div>
        <div className="bottom-item">
          <span className="bottom-icon"><img src={screenshotIcon} className="bottom-icon" alt="" /></span>
          <span className="bottom-label">Снимок</span>
        </div>
        <div className="bottom-item">
          <span className="bottom-icon"><img src={tutorIcon} className="bottom-icon" alt="" /></span>
          <span className="bottom-label">Справка</span>
        </div>
      </div>
    </div>
  );
}