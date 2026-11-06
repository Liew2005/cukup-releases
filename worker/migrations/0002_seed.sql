INSERT INTO categories (name, kind, sort_order) VALUES
  ('Food','spend',1),('Groceries','spend',2),('Transport','spend',3),('Bills','spend',4),
  ('Fun','spend',5),('Shopping','spend',6),('Other','spend',7),
  ('Allowance','income',8),('Freelance','income',9),('Other income','income',10);

INSERT INTO settings (key, value) VALUES
  ('weekly_cap_cents','25000'),
  ('week_starts_on','monday'),
  ('timezone','Asia/Kuala_Lumpur'),
  ('emergency_target_cents','300000'),
  ('nudge_enabled','1'),
  ('nudge_time','21:00'),
  ('summary_enabled','1'),
  ('alert_80_enabled','0');


INSERT INTO goals (id, name, target_cents, opening_cents, priority) VALUES
  ('goal-ef','Emergency fund',300000,0,1),
  ('goal-etf','ETF fund',NULL,0,2);
