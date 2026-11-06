package my.cukup.cukup

import androidx.core.content.FileProvider

/** Lets the system installer read the downloaded update from the app's cache. Its own class so it cannot clash with other plugins' providers. */
class UpdateFileProvider : FileProvider()
