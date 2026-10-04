import 'package:flutter/material.dart';

/// Application strings, behind a [LocalizationsDelegate] so a second locale
/// is a new class rather than a refactor.
///
/// Only English ships today. Every user-visible string in lib/ui comes from
/// here, so adding a locale means translating this one file and registering
/// it in [_AppLocalizationsDelegate]. No codegen, no build step.
abstract class AppStrings {
  String get appName;
  String get offline;
  String get offlineTooltip;
  String get addImages;
  String get saveSettings;
  String get settingsSaved;
  String get queue;
  String get preview;
  String get settings;
  String get outputSettings;
  String get nothingSelected;
  String get dropImagesHere;
  String get dropImagesHint;
  String get process;
  String processCount(int n);
  String get saveAll;
  String filesSaved(int n);
  String get fileSaved;
  String get removeFinished;
  String get clearAll;
  String get rerunEverything;
  String get queueActions;
  String get remove;
  String get cancel;
  String get before;
  String get split;
  String get after;
  String get original;
  String get live;
  String get result;
  String get saveToGallery;
  String savedToGallery(String name);
  String get nothingToPreview;
  String get comparisonDivider;
  String get comparisonHint;
  String get addImagesEmpty;
  String filesAdded(int n);
  String get fileAdded;
  String get preset;
  String get custom;
  String get size;
  String get output;
  String get transform;
  String get adjust;
  String get watermark;
  String get mode;
  String get width;
  String get height;
  String get scale;
  String get allowUpscale;
  String get allowUpscaleHint;
  String get quality;
  String get qualityAuto;
  String get maxKb;
  String get qualitySolvedHint;
  String get pngCompression;
  String get losslessWebp;
  String get encodeEffort;
  String get jpegChroma;
  String get stripMetadata;
  String get stripMetadataHint;
  String get stripMetadataOff;
  String get stripLocation;
  String get stripCamera;
  String get stripDates;
  String get stripThumbnail;
  String get keepExtension;
  String get rotate;
  String get flipH;
  String get unflipH;
  String get flipV;
  String get unflipV;
  String get autoLevels;
  String get reset;
  String get brightness;
  String get contrast;
  String get saturation;
  String get exposure;
  String get hue;
  String get gamma;
  String get amount;
  String get grayscale;
  String get sepia;
  String get blurRadius;
  String get sharpen;
  String get watermarkText;
  String get watermarkHint;
  String get position;
  String get topLeft;
  String get topRight;
  String get center;
  String get bottomLeft;
  String get bottomRight;
  String get watermarkSize;
  String get opacity;
  String get margin;
  String get filenameTemplate;
  String get overwrite;
  String get writeImmediately;
  String get writeImmediatelyHint;
  String get memoryBudget;
  String get savesToCurrentFolder;
  String get browse;
  String get extraOutputs;
  String get extraOutputsHint;
  String get extraOutputsEmpty;
  String get extraOutputsFull;
  String get addOutput;
  String get clearAllOutputs;
  String removePreset(String name);
  String get padColour;
  String get target;
  String get format;
  String get sizeLabel;
  String get qualityLabel;
  String get saved;
  String get onboarding;
  String get dropToAdd;
  String get dropDepthHint;
  String get keepFormat;
  String get lossless;
  String get noImages;
  String filesQueued(int n);
  String get failed;
  String doneCount(int n);
  String get preserveAnimation;
  String get preserveAnimationHint;
  String get preserveAnimationBody;
  String get unlinkDimensions;
  String get linkAspect;
  String get keepAllCaps;
}

class EnStrings extends AppStrings {
  @override
  String get appName => 'PixelForge';
  @override
  String get offline => 'Offline';
  @override
  String get offlineTooltip =>
      'No network permission. Images never leave this device.';
  @override
  String get addImages => 'Add images';
  @override
  String get saveSettings => 'Settings';
  @override
  String get settingsSaved => 'Settings saved';
  @override
  String get queue => 'Queue';
  @override
  String get preview => 'Preview';
  @override
  String get settings => 'Settings';
  @override
  String get outputSettings => 'Output settings';
  @override
  String get nothingSelected => 'Nothing selected';
  @override
  String get dropImagesHere => 'Drop images here';
  @override
  String get dropImagesHint => 'or use the Add button above';
  @override
  String get process => 'Process';
  @override
  String processCount(int n) => 'Process $n';
  @override
  String get saveAll => 'Save all';
  @override
  String filesSaved(int n) => 'Saved $n files';
  @override
  String get fileSaved => 'Saved 1 file';
  @override
  String get removeFinished => 'Remove finished';
  @override
  String get clearAll => 'Clear all';
  @override
  String get rerunEverything => 'Re-run everything';
  @override
  String get queueActions => 'Queue actions';
  @override
  String get remove => 'Remove';
  @override
  String get cancel => 'Cancel';
  @override
  String get before => 'Before';
  @override
  String get split => 'Split';
  @override
  String get after => 'After';
  @override
  String get original => 'Original';
  @override
  String get live => 'Live';
  @override
  String get result => 'Result';
  @override
  String get saveToGallery => 'Save to gallery';
  @override
  String savedToGallery(String name) => 'Saved $name to the gallery';
  @override
  String get nothingToPreview => 'Nothing to preview';
  @override
  String get comparisonDivider => 'Comparison divider';
  @override
  String get comparisonHint => 'Drag to compare, or use arrow keys';
  @override
  String get addImagesEmpty =>
      'Add images, choose an output size, then press Process. '
      'Everything runs on this device.';
  @override
  String filesAdded(int n) => 'Added $n files';
  @override
  String get fileAdded => 'Added 1 file';
  @override
  String get preset => 'Preset';
  @override
  String get custom => 'Custom';
  @override
  String get size => 'Size';
  @override
  String get output => 'Output';
  @override
  String get transform => 'Transform';
  @override
  String get adjust => 'Adjust';
  @override
  String get watermark => 'Watermark';
  @override
  String get mode => 'Mode';
  @override
  String get width => 'Width';
  @override
  String get height => 'Height';
  @override
  String get scale => 'Scale';
  @override
  String get allowUpscale => 'Allow upscaling';
  @override
  String get allowUpscaleHint => 'Off keeps images from being enlarged';
  @override
  String get quality => 'Quality';
  @override
  String get qualityAuto => 'Quality (auto)';
  @override
  String get maxKb => 'Max KB';
  @override
  String get qualitySolvedHint =>
      'Quality is solved per image to land under the budget.';
  @override
  String get pngCompression => 'PNG compression';
  @override
  String get losslessWebp => 'Lossless WebP';
  @override
  String get encodeEffort => 'Encode effort';
  @override
  String get jpegChroma => 'JPEG chroma';
  @override
  String get stripMetadata => 'Strip EXIF / metadata';
  @override
  String get stripMetadataHint => 'Choose what goes below';
  @override
  String get stripMetadataOff => 'Everything is kept as-is';
  @override
  String get stripLocation => 'Location (GPS)';
  @override
  String get stripCamera => 'Camera make, model and settings';
  @override
  String get stripDates => 'Dates and times taken';
  @override
  String get stripThumbnail => 'Embedded thumbnail';
  @override
  String get keepExtension => 'Keep original extension';
  @override
  String get rotate => 'Rotate';
  @override
  String get flipH => 'Flip H';
  @override
  String get unflipH => 'Unflip H';
  @override
  String get flipV => 'Flip V';
  @override
  String get unflipV => 'Unflip V';
  @override
  String get autoLevels => 'Auto levels when untouched';
  @override
  String get reset => 'Reset';
  @override
  String get brightness => 'Brightness';
  @override
  String get contrast => 'Contrast';
  @override
  String get saturation => 'Saturation';
  @override
  String get exposure => 'Exposure';
  @override
  String get hue => 'Hue';
  @override
  String get gamma => 'Gamma';
  @override
  String get amount => 'Amount';
  @override
  String get grayscale => 'Grayscale';
  @override
  String get sepia => 'Sepia';
  @override
  String get blurRadius => 'Blur radius';
  @override
  String get sharpen => 'Sharpen';
  @override
  String get watermarkText => 'Text';
  @override
  String get watermarkHint => '© yourname';
  @override
  String get position => 'Position';
  @override
  String get topLeft => 'Top left';
  @override
  String get topRight => 'Top right';
  @override
  String get center => 'Center';
  @override
  String get bottomLeft => 'Bottom left';
  @override
  String get bottomRight => 'Bottom right';
  @override
  String get watermarkSize => 'Size';
  @override
  String get opacity => 'Opacity';
  @override
  String get margin => 'Margin';
  @override
  String get filenameTemplate => 'Filename template';
  @override
  String get overwrite => 'Overwrite existing files';
  @override
  String get writeImmediately => 'Write each file as it finishes';
  @override
  String get writeImmediatelyHint =>
      'Frees memory during large batches; re-running needs the files re-added';
  @override
  String get memoryBudget => 'Memory budget';
  @override
  String get savesToCurrentFolder => 'Saves to the current folder';
  @override
  String get browse => 'Browse';
  @override
  String get extraOutputs => 'Extra outputs';
  @override
  String get extraOutputsHint =>
      'Each file is exported once per output below, plus the main '
      'settings above, from a single decode.';
  @override
  String get extraOutputsEmpty =>
      'Add presets to export alongside the main output.';
  @override
  String get extraOutputsFull => 'Every preset is already an output.';
  @override
  String get addOutput => 'Add an output';
  @override
  String get clearAllOutputs => 'Clear all';
  @override
  String removePreset(String name) => 'Remove $name';
  @override
  String get padColour => 'Pad colour';
  @override
  String get target => 'Target';
  @override
  String get format => 'Format';
  @override
  String get sizeLabel => 'Size';
  @override
  String get qualityLabel => 'Quality';
  @override
  String get saved => 'Saved';
  @override
  String get onboarding => 'Onboarding';
  @override
  String get dropToAdd => 'Drop to add';
  @override
  String get dropDepthHint => 'Folders are walked up to 3 levels deep';
  @override
  String get keepFormat => 'keep';
  @override
  String get lossless => 'lossless';
  @override
  String get noImages => 'No images yet';
  @override
  String filesQueued(int n) => n == 1 ? '1 file' : '$n files';
  @override
  String get failed => 'Failed';
  @override
  String doneCount(int n) => '$n done';
  @override
  String get preserveAnimation => 'Preserve animation';
  @override
  String get preserveAnimationHint =>
      'Turning it off flattens to the first frame.';
  @override
  String get preserveAnimationBody =>
      'Every frame of an animated GIF or WebP is carried through. '
      'Turning it off flattens to the first frame.';
  @override
  String get unlinkDimensions => 'Unlink dimensions';
  @override
  String get linkAspect => 'Lock aspect ratio';
  @override
  String get keepAllCaps => 'KEEP';
}

class AppLocalizations {
  const AppLocalizations._();

  static AppStrings of(BuildContext context) {
    final strings =
        Localizations.of<AppStrings>(context, AppStrings);
    return strings ?? EnStrings();
  }

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [Locale('en')];
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppStrings> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<AppStrings> load(Locale locale) async => EnStrings();

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
