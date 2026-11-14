-- Categories can now be added, renamed and removed from the app.
-- cap_default: does spending in this category count toward the weekly cap unless the entry says otherwise?
ALTER TABLE categories ADD COLUMN cap_default INTEGER NOT NULL DEFAULT 1 CHECK (cap_default IN (0,1));
UPDATE categories SET cap_default = 0 WHERE name = 'Bills';
