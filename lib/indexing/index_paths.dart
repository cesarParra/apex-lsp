/// Canonical path segments for the workspace index directory tree.
///
/// All code that reads from or writes to the index must use these constants
/// so that renaming the layout requires a single change here.
const String indexRootFolderName = '.sf-zed';
const String apexIndexFolderName = 'apex';
const String sobjectIndexFolderName = 'sobjects';
