import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/commands/create_restroom_command.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/duplicate_scan_result.dart';
import '../../domain/repositories/restroom_repository.dart';
import '../../domain/services/duplicate_detection_service.dart';
import '../components/bottom_sheets/duplicate_warning_sheet.dart';
import '../components/feedback/empty_state_view.dart';
import '../components/navigation/loo_bottom_nav_bar.dart';
import '../state/auth_notifier.dart';
import '../state/map_discovery_notifier.dart';
import '../state/restroom_id_generator.dart';
import 'add_restroom_form_screen.dart';
import 'add_restroom_location_screen.dart';
import 'explore_restrooms_screen.dart';
import 'map_discovery_screen.dart';

/// Main application shell housing the bottom navigation bar and active tab screens.
class MainShellScreen extends StatefulWidget {
  final MapWidgetBuilder? addLocationMapBuilder;
  final MapWidgetBuilder? discoveryMapBuilder;
  final RestroomIdGenerator? formIdGenerator;
  final DuplicateDetectionService? duplicateDetectionService;

  const MainShellScreen({
    super.key,
    this.addLocationMapBuilder,
    this.discoveryMapBuilder,
    this.formIdGenerator,
    this.duplicateDetectionService,
  });

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentTabIndex = 0;
  bool _isOpeningAddLocation = false;
  bool _isSubmitting = false;
  Coordinates? _discoveryCameraTarget;
  CreateRestroomCommand? _preservedDraftCommand;
  Coordinates? _preservedDraftCoordinates;

  void _handleDiscoveryCameraTargetChanged(Coordinates target) {
    _discoveryCameraTarget = target;
  }

  Future<void> _openAddRestroom() async {
    if (_isOpeningAddLocation || _isSubmitting) return;

    // Check if user has a preserved draft from a previous dismissed duplicate warning or failed submission
    if (_preservedDraftCommand != null && _preservedDraftCoordinates != null) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Resume Contribution?'),
          content: Text(
            'You have a saved draft for "${_preservedDraftCommand!.draft.name}". Would you like to resume editing this draft or discard it to start fresh?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Discard & Start New'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Resume Draft'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (resume == true) {
        await _continueWithForm(
          confirmedCoordinates: _preservedDraftCoordinates!,
          initialCommand: _preservedDraftCommand,
        );
        return;
      } else if (resume == false) {
        // Explicit abandonment of preserved draft
        _preservedDraftCommand = null;
        _preservedDraftCoordinates = null;
      } else {
        // User dismissed resume prompt dialog; keep draft preserved
        return;
      }
    }

    _isOpeningAddLocation = true;
    try {
      final Coordinates? confirmedCoordinates = await Navigator.of(context)
          .push<Coordinates>(
            AddRestroomLocationScreen.route(
              initialCoordinates: _discoveryCameraTarget,
              mapBuilder: widget.addLocationMapBuilder,
            ),
          );

      if (!mounted) return;

      if (confirmedCoordinates != null) {
        await _continueWithForm(confirmedCoordinates: confirmedCoordinates);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningAddLocation = false;
        });
      }
    }
  }

  Future<void> _continueWithForm({
    required Coordinates confirmedCoordinates,
    CreateRestroomCommand? initialCommand,
  }) async {
    final CreateRestroomCommand? command = await Navigator.of(context)
        .push<CreateRestroomCommand>(
          AddRestroomFormScreen.route(
            coordinates: confirmedCoordinates,
            idGenerator: widget.formIdGenerator,
            initialCommand: initialCommand,
          ),
        );

    if (!mounted) return;

    if (command != null) {
      await _processDraftSubmissionFlow(
        command: command,
        confirmedCoordinates: confirmedCoordinates,
      );
    }
  }

  Future<void> _processDraftSubmissionFlow({
    required CreateRestroomCommand command,
    required Coordinates confirmedCoordinates,
  }) async {
    final duplicateService =
        widget.duplicateDetectionService ?? const DuplicateDetectionService();

    DuplicateScanResult scanResult = const DuplicateScanResult(candidates: []);
    try {
      final repo = context.read<RestroomRepository>();
      scanResult = await duplicateService.findDuplicatesNearby(
        draft: command.draft,
        repository: repo,
      );
    } catch (e) {
      // Advisory scan: fail open so user is never blocked
      scanResult = DuplicateScanResult.failedOpen(errorMessage: e.toString());
    }

    if (!mounted) return;

    if (scanResult.hasDuplicates) {
      await _handleDuplicateWarning(
        command: command,
        confirmedCoordinates: confirmedCoordinates,
        scanResult: scanResult,
      );
    } else {
      String? scanNote;
      if (scanResult.hasQueryError) {
        scanNote = 'Duplicate check could not be completed, but contribution proceeds (advisory fail-open).';
      } else if (!scanResult.isComplete) {
        scanNote = 'No likely duplicates found in the results checked, but the duplicate scan was incomplete.';
      }

      await _submitRestroom(
        command: command,
        confirmedCoordinates: confirmedCoordinates,
        advisoryScanNote: scanNote,
      );
    }
  }

  Future<void> _handleDuplicateWarning({
    required CreateRestroomCommand command,
    required Coordinates confirmedCoordinates,
    required DuplicateScanResult scanResult,
  }) async {
    final action = await DuplicateWarningSheet.show(
      context,
      candidates: scanResult.candidates,
    );

    if (!mounted) return;

    if (action is ViewExistingRestroomAction) {
      // Explicit abandonment of draft
      _preservedDraftCommand = null;
      _preservedDraftCoordinates = null;

      setState(() => _currentTabIndex = 0);
      try {
        final discoveryNotifier = context.read<MapDiscoveryNotifier>();
        discoveryNotifier.focusOnRestroom(
          action.restroom,
          zoom: AppConstants.defaultZoomLevel,
          openPreview: true,
        );
      } catch (_) {}
      return;
    } else if (action is ProceedWithSubmissionAction) {
      // Acknowledged warning; proceeding to submission (P2.5)
      await _submitRestroom(
        command: command,
        confirmedCoordinates: confirmedCoordinates,
      );
      return;
    } else {
      // action == null: User dismissed warning sheet.
      // Explicitly preserve stable command, coordinates, and restroomId.
      _preservedDraftCommand = command;
      _preservedDraftCoordinates = confirmedCoordinates;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Draft for "${command.draft.name}" preserved. Tap Review to re-check duplicates or resume.',
          ),
          action: SnackBarAction(
            label: 'Review',
            onPressed: () {
              if (mounted) {
                _handleDuplicateWarning(
                  command: command,
                  confirmedCoordinates: confirmedCoordinates,
                  scanResult: scanResult,
                );
              }
            },
          ),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _submitRestroom({
    required CreateRestroomCommand command,
    required Coordinates confirmedCoordinates,
    String? advisoryScanNote,
  }) async {
    // Acquire operation lock before any async stage
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final config = Provider.of<AppConfig?>(context, listen: false);

      // BLOCKER-1: Fail closed unless verified staging and approved staging project ID
      if (config == null || !config.isStagingSubmissionAllowed) {
        _preservedDraftCommand = command;
        _preservedDraftCoordinates = confirmedCoordinates;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        final String rejectionMessage;
        if (config == null) {
          rejectionMessage = 'Community restroom contributions are unavailable due to missing application configuration.';
        } else if (config.isProduction) {
          rejectionMessage = 'Community restroom contributions are currently disabled in production until server-side abuse protections are active (Milestone P2.6).';
        } else if (!config.isStaging) {
          rejectionMessage = 'Community restroom contributions are only permitted in the verified staging environment.';
        } else if (config.firebaseProjectId !=
            AppConstants.stagingFirebaseProjectId) {
          rejectionMessage =
              'Community restroom contributions are restricted to the verified staging Firebase project (${AppConstants.stagingFirebaseProjectId}).';
        } else {
          rejectionMessage = 'Community restroom contributions are only permitted in the verified staging environment.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(rejectionMessage),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Resume',
              onPressed: () {
                if (mounted) {
                  _openAddRestroom();
                }
              },
            ),
          ),
        );
        return;
      }

      // MAJOR-2: Ensure anonymous session before write while operation lock is held
      final authNotifier = Provider.of<AuthNotifier?>(context, listen: false);
      if (authNotifier != null && !authNotifier.isAuthenticated) {
        await authNotifier.signInAnonymously();
        if (!mounted) return;
        if (!authNotifier.isAuthenticated) {
          _preservedDraftCommand = command;
          _preservedDraftCoordinates = confirmedCoordinates;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Unable to sign in anonymously. Please check your internet connection and try again.',
              ),
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  if (mounted) {
                    _submitRestroom(
                      command: command,
                      confirmedCoordinates: confirmedCoordinates,
                      advisoryScanNote: advisoryScanNote,
                    );
                  }
                },
              ),
            ),
          );
          return;
        }
      }

      // Display non-dismissible progress indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 14),
              Text('Submitting restroom...'),
            ],
          ),
          duration: Duration(days: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Object? submissionError;
      try {
        final repo = context.read<RestroomRepository>();
        await repo.submitRestroom(command);
      } catch (e) {
        submissionError = e;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).clearSnackBars();

      if (submissionError != null) {
        _handleSubmissionFailure(
          command: command,
          confirmedCoordinates: confirmedCoordinates,
          error: submissionError,
        );
        return;
      }

      // Success! Clear preserved draft
      _preservedDraftCommand = null;
      _preservedDraftCoordinates = null;

      final successMessage = advisoryScanNote != null
          ? '$advisoryScanNote Restroom "${command.draft.name}" submitted successfully.'
          : 'Restroom "${command.draft.name}" submitted successfully.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Switch to Map tab (tab 0)
      setState(() => _currentTabIndex = 0);

      // Canonical discovery sync (P2.5-C)
      try {
        final discoveryNotifier = context.read<MapDiscoveryNotifier>();
        discoveryNotifier.focusOnSubmittedRestroom(
          coordinates: command.draft.coordinates,
          restroomId: command.restroomId,
          facilityName: command.draft.name,
          zoom: 16.5,
        );
      } catch (e) {
        debugPrint('Failed to initiate map focus on submitted restroom: $e');
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Restroom saved, but map could not navigate automatically. Tap to center.',
            ),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Center',
              onPressed: () {
                if (mounted) {
                  try {
                    context
                        .read<MapDiscoveryNotifier>()
                        .focusOnSubmittedRestroom(
                          coordinates: command.draft.coordinates,
                          restroomId: command.restroomId,
                          facilityName: command.draft.name,
                          zoom: 16.5,
                        );
                  } catch (_) {}
                }
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _handleSubmissionFailure({
    required CreateRestroomCommand command,
    required Coordinates confirmedCoordinates,
    required Object error,
  }) {
    // Preserve draft with identical command and restroomId
    _preservedDraftCommand = command;
    _preservedDraftCoordinates = confirmedCoordinates;

    String errorMessage;
    String actionLabel = 'Retry';
    VoidCallback onAction = () {
      if (mounted) {
        _submitRestroom(
          command: command,
          confirmedCoordinates: confirmedCoordinates,
        );
      }
    };

    if (error is SubmissionInvariantException) {
      final detail = error.message.replaceFirst(
        RegExp(r'^(Data )?[Ii]nvariant violation:\s*'),
        '',
      );
      errorMessage = 'Data invariant violation: $detail';
      actionLabel = 'Resume';
      onAction = () {
        if (mounted) {
          _openAddRestroom();
        }
      };
    } else if (error is UnauthenticatedException) {
      errorMessage = 'Authentication required. Please check your connection and try again.';
    } else if (error is RepositoryException) {
      if (error.code == 'firebase-init-failed') {
        errorMessage = 'Submission is unavailable because staging Firebase configuration failed to initialize.';
        actionLabel = 'Resume';
        onAction = () {
          if (mounted) {
            _openAddRestroom();
          }
        };
      } else if (error.code == 'production-writes-blocked' ||
          error.code == 'unconfigured-environment' ||
          error.code == 'staging-project-mismatch' ||
          error.code == 'non-staging-environment') {
        errorMessage = error.message;
        actionLabel = 'Resume';
        onAction = () {
          if (mounted) {
            _openAddRestroom();
          }
        };
      } else if (error.code == 'invalid-draft' ||
          error.code == 'invalid-restroom-id') {
        errorMessage = 'Invalid restroom details: ${error.message}';
        actionLabel = 'Resume';
        onAction = () {
          if (mounted) {
            _openAddRestroom();
          }
        };
      } else if (error.code == 'permission-denied' ||
          error.code == 'unauthorized') {
        errorMessage = 'Submission rejected by server permissions. Please ensure your session is valid.';
      } else if (error.code == 'network-error' ||
          error.code == 'unavailable' ||
          error.code == 'deadline-exceeded') {
        errorMessage =
            'Connection failed. Please check your internet connection.';
      } else {
        errorMessage =
            'Unable to save restroom (${error.message}). Please try again.';
      }
    } else {
      errorMessage =
          'Connection failed. Please check your internet connection.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          MapDiscoveryScreen(
            mapBuilder: widget.discoveryMapBuilder,
            onCameraTargetChanged: _handleDiscoveryCameraTargetChanged,
          ),
          ExploreRestroomsScreen(
            onSelectRestroom: (restroom) {
              setState(() => _currentTabIndex = 0);
            },
            onSwitchToMap: () {
              setState(() => _currentTabIndex = 0);
            },
          ),
          const SizedBox.shrink(),
          const _PhasePlaceholderScreen(
            icon: Icons.favorite_rounded,
            title: 'Saved Places',
            phaseDescription: 'Future phases will allow saving bookmarked restroom facilities.',
          ),
          const _PhasePlaceholderScreen(
            icon: Icons.settings_rounded,
            title: 'More & Support',
            phaseDescription:
                '${AppConstants.appName} v1.0.0 (Phase 0 Foundation)\nCommunity-powered, privacy-first.',
          ),
        ],
      ),
      bottomNavigationBar: LooBottomNavBar(
        currentIndex: _currentTabIndex,
        onTabSelected: (index) {
          if (_isSubmitting) return;
          if (index == 2) {
            _openAddRestroom();
          } else {
            setState(() => _currentTabIndex = index);
          }
        },
      ),
    );
  }
}

class _PhasePlaceholderScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String phaseDescription;

  const _PhasePlaceholderScreen({
    required this.icon,
    required this.title,
    required this.phaseDescription,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyStateView(
            icon: icon,
            title: title,
            description: phaseDescription,
          ),
        ),
      ),
    );
  }
}
