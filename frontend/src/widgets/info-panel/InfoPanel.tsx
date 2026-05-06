import '../../App.css';
import type { DetectionClassType, DetectionSummary } from '../../entities/detection/types';

function formatScore(value: number) {
  return value.toFixed(2);
}

type Props = {
  item: DetectionSummary | null;
  items: DetectionSummary[];
  onCloseSelection: () => void;
};

function getCounts(items: DetectionSummary[]) {
  return items.reduce<Record<DetectionClassType, number>>(
    (acc, item) => {
      acc[item.classType] += 1;
      return acc;
    },
    {
      fire: 0,
      infection: 0,
      logging: 0,
    },
  );
}

export function InfoPanel({ item, items, onCloseSelection }: Props) {
  const counts = getCounts(items);

  return (
    <div className="details-panel info-panel">
      <div className="details-panel__header">
        <div className="details-panel__title-group">
          <div className="details-panel__eyebrow">
            {item ? 'Выбранная детекция' : 'Статистика текущей выборки'}
          </div>
          <div className="details-panel__title">
            {item ? item.title ?? item.id : 'Сводка по карте'}
          </div>
        </div>

        {item ? (
          <button
            type="button"
            className="details-panel__close"
            onClick={onCloseSelection}
            aria-label="Закрыть выбранную детекцию"
          >
            ×
          </button>
        ) : null}
      </div>

      {item ? (
        <div className="details-panel__grid">
          <div className="details-panel__row">
            <span className="details-panel__label">class_type</span>
            <span className="details-panel__value">{item.classType}</span>
          </div>

          <div className="details-panel__row">
            <span className="details-panel__label">detected_at</span>
            <span className="details-panel__value">
              {new Date(item.detectedAt).toLocaleString()}
            </span>
          </div>

          <div className="details-panel__row">
            <span className="details-panel__label">score</span>
            <span className="details-panel__value">{formatScore(item.score)}</span>
          </div>

          <div className="details-panel__row">
            <span className="details-panel__label">severity</span>
            <span className="details-panel__value">{item.severity}</span>
          </div>

          <div className="details-panel__row">
            <span className="details-panel__label">image_path</span>
            <span className="details-panel__value details-panel__value--link">
              {item.imagePath ? (
                <a href={item.imagePath} target="_blank" rel="noreferrer">
                  Открыть
                </a>
              ) : (
                '—'
              )}
            </span>
          </div>
        </div>
      ) : (
        <div className="details-panel__description-block">
          <div className="details-panel__description">
            Выбери объект на карте или в списке слева, чтобы увидеть параметры выбранной детекции.
          </div>
        </div>
      )}

      <div className="info-panel__stats">
        <div className="info-panel__stats-title">Статистика текущей выборки</div>

        <div className="info-panel__stats-grid">
          <div className="info-panel__stat-card">
            <span>Пожары</span>
            <strong>{counts.fire}</strong>
          </div>

          <div className="info-panel__stat-card">
            <span>Заражения</span>
            <strong>{counts.infection}</strong>
          </div>

          <div className="info-panel__stat-card">
            <span>Вырубки</span>
            <strong>{counts.logging}</strong>
          </div>
        </div>
      </div>
    </div>
  );
}