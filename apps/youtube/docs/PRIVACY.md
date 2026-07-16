# Privacy

YouTube Local Exporter stores extension preferences in `chrome.storage.sync`, including default output folder text, preferred export mode, default formats, and subtitle settings.

Media export jobs are processed locally by the native host. The extension does not collect analytics, send generated media to a remote service, or use cloud transcription.

The native host writes exported files to the selected local output folder and stores common helper tools under `%LOCALAPPDATA%\com.dowen.local_exporter\toolchain`.

Use this tool only for videos you own or are authorized to export.
