import { Hono } from 'hono';
import { requireAuth } from './auth';
import { auth } from './routes/auth';
import { parse } from './routes/parse';
import { exportRoute } from './routes/export';
import { bills, categories, recurring, rules, settings } from './routes/reference';
import { summary } from './routes/summary';
import { ledger } from './routes/ledger';
import { transactions } from './routes/transactions';
import { HttpError, type AppEnv } from './types';

const app = new Hono<AppEnv>();

// Public routes first. Everything registered after requireAuth needs a valid token.
app.get('/health', (c) => c.json({ ok: true, app: 'cukup' }));
app.route('/auth', auth);

app.use('*', requireAuth);
app.route('/transactions', transactions);
app.route('/summary', summary);
app.route('/categories', categories);
app.route('/rules', rules);
app.route('/bills', bills);
app.route('/recurring', recurring);
app.route('/settings', settings);
app.route('/ledger', ledger);
app.route('/parse-receipt', parse);
app.route('/', exportRoute);

app.notFound((c) => c.json({ error: 'not_found', message: 'No such route' }, 404));
app.onError((err, c) => {
  if (err instanceof HttpError) return c.json({ error: err.code, message: err.message }, err.status);
  console.error(err);
  return c.json({ error: 'internal', message: 'Something went wrong' }, 500);
});

export default app;

