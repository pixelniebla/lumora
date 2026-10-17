import 'dart:io';

/// True when [exePath] lives in a Windows app package folder (...\WindowsApps\...), i.e. Lumora was
/// installed from the Microsoft Store (MSIX). Microsoft updates those; the in-app updater must stay off.
bool isPackagedPath(String exePath) => exePath.toLowerCase().replaceAll('/', r'\').contains(r'\windowsapps\');

/// Whether this process is the Store (MSIX) build.
final bool isStoreBuild = Platform.isWindows && isPackagedPath(Platform.resolvedExecutable);
