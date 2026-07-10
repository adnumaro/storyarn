%{
title: "Assets",
category_label: "Project Management",
order: 2,
description: "Upload, find, inspect, reuse, and safely remove project images and audio."
}

---

The **Assets** workspace is the shared media library for a project. Open it from the project sidebar to manage images and audio separately from the sheets, flows, and scenes that use them.

## Uploading files

Use **Upload** in the top toolbar and choose one file. The standard asset uploader accepts:

- Images: JPEG, PNG, GIF, and WebP.
- Audio: MP3, WAV, OGG, and WebM.

The dashboard uploader accepts files up to **20 MB**. Storage availability also depends on the workspace plan; check **Project Settings > Usage Limits** when an upload is rejected because the storage allowance has been reached.

Uploads performed from an image-specific editor, such as a sheet avatar, banner, or scene background, can use a different upload path that prepares an appropriate image variant.

## Finding assets

Use the sidebar search to filter by filename. The type filters separate **All**, **Images**, **Audio**, and other stored files. The counters beside each filter show the current project totals.

Each card displays a preview when available, the filename, file size, and type. Selecting a card opens the detail panel.

## Details and usage

The detail panel shows the MIME type, size, upload date, an image preview or audio player, and known usages. Usage links can lead to:

- Flow nodes using audio.
- Sheet avatars and banners.
- Scene backgrounds.
- Scene pin icons.

Follow these links before replacing or deleting an asset. They identify the content that may need to be updated.

## Reusing assets

Asset pickers inside Sheets, Flows, and Scenes read from the same project library. Reusing an existing asset avoids uploading duplicate files and keeps usage tracking useful.

## Deleting assets

Only users with edit permission can delete an asset. Storyarn shows a confirmation and warns when known usages exist. Deletion is permanent for the stored asset, so update or remove its usages first and confirm the affected content afterwards.

Project export can keep asset URLs as references, embed files as Base64, or bundle them in a ZIP. See [Export](/docs/import-export/import-export-overview#how-to-export).
