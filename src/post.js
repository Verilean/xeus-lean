// getDylinkMetadata is only available with MAIN_MODULE (dynamic linking).
// We link statically, so it may not exist.
if (typeof getDylinkMetadata !== 'undefined') {
  Module['getDylinkMetadata'] = getDylinkMetadata;
}
