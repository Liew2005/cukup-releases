// Which categories stay out of the weekly cap unless an entry says otherwise.
// Each category carries this as a setting (Settings > Categories). The names are kept here so the
// forms and the payment detector can ask without touching the database. Bills is the default until categories load.
Set<String> _capOff = {'bills'};

/// Called whenever the category list changes, with the names whose "Counts toward weekly cap" is off.
void setCapOff(Iterable<String> names) => _capOff = {for (final n in names) n.trim().toLowerCase()};

/// Does spending in [categoryName] count toward the weekly cap by default?
bool capDefault(String? categoryName) => !_capOff.contains((categoryName ?? '').trim().toLowerCase());
