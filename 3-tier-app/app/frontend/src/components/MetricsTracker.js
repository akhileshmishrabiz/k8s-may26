import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { recordPageView } from '../services/metricsClient';

function normalizeRoute(pathname) {
  if (!pathname) {
    return '/';
  }
  return pathname.replace(/\/[0-9a-f-]{36}(?=\/|$)/gi, '/:id');
}

function MetricsTracker() {
  const location = useLocation();

  useEffect(() => {
    recordPageView(normalizeRoute(location.pathname));
  }, [location.pathname]);

  return null;
}

export default MetricsTracker;
