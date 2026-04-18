import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/nomade_provider.dart';
import '../services/revenuecat_service.dart';

Future<void> showProPaywallSheet(
  BuildContext context, {
  String? sourceLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<NomadeProvider>(),
      child: _ProPaywallSheet(sourceLabel: sourceLabel),
    ),
  );
}

class _ProPaywallSheet extends StatefulWidget {
  const _ProPaywallSheet({this.sourceLabel});

  final String? sourceLabel;

  @override
  State<_ProPaywallSheet> createState() => _ProPaywallSheetState();
}

class _ProPaywallSheetState extends State<_ProPaywallSheet> {
  Offering? _offering;
  Package? _selectedPackage;
  String? _error;
  bool _loading = true;
  bool _purchaseInFlight = false;
  bool _restoreInFlight = false;
  String? _managementUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOffering());
  }

  Future<void> _loadOffering() async {
    final provider = context.read<NomadeProvider>();
    try {
      await provider.loadCurrentUser(notifyListenersNow: false);
      final userId = provider.currentUserId?.trim() ?? '';
      if (userId.isEmpty) {
        throw StateError(
            'Authenticated account ID unavailable. Re-login and try again.');
      }
      await RevenueCatService.configureForUser(userId);
      final offering = await RevenueCatService.getCurrentOffering();
      if (!mounted) {
        return;
      }
      if (offering == null || offering.availablePackages.isEmpty) {
        setState(() {
          _loading = false;
          _offering = offering;
          _selectedPackage = null;
          _error = 'No RevenueCat offering is available for this account yet.';
        });
        return;
      }
      final preferred = offering.annual ??
          offering.monthly ??
          offering.availablePackages.first;
      setState(() {
        _loading = false;
        _offering = offering;
        _selectedPackage = preferred;
        _error = null;
      });
    } on PlatformException catch (error) {
      final message = await _normalizeLoadOfferingError(error);
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _offering = null;
        _selectedPackage = null;
        _error = message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('StateError: ', '');
      });
    }
  }

  Future<String> _normalizeLoadOfferingError(PlatformException error) async {
    final raw = error.message?.trim();
    final code = PurchasesErrorHelper.getErrorCode(error);
    if (code == PurchasesErrorCode.configurationError) {
      if (await _isAffectedIosSimulator()) {
        return 'This iOS 18.4-18.5 simulator cannot load App Store products. '
            'Test purchases on a physical iPhone/iPad, an iOS 26+ simulator, '
            'or with a StoreKit configuration file run directly from Xcode.';
      }
      return 'RevenueCat could not load the App Store products for this '
          'offering. Check that the product IDs are available in both '
          'RevenueCat and App Store Connect for this build.';
    }
    return (raw == null || raw.isEmpty) ? error.toString() : raw;
  }

  Future<bool> _isAffectedIosSimulator() async {
    if (kIsWeb || !Platform.isIOS) {
      return false;
    }
    try {
      final iosInfo = await DeviceInfoPlugin().iosInfo;
      if (iosInfo.isPhysicalDevice) {
        return false;
      }
      final version = iosInfo.systemVersion.trim();
      return version.startsWith('18.4') || version.startsWith('18.5');
    } catch (_) {
      return false;
    }
  }

  Future<void> _handlePurchase() async {
    final package = _selectedPackage;
    if (package == null || _purchaseInFlight) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _purchaseInFlight = true;
      _error = null;
    });
    try {
      final result = await RevenueCatService.purchasePackage(package);
      _managementUrl = result.customerInfo.managementURL;
      await _refreshBackendEntitlements();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Purchase complete. Refreshing Pro access...')),
      );
      Navigator.of(context).pop();
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        setState(() {
          _purchaseInFlight = false;
        });
        return;
      }
      setState(() {
        _purchaseInFlight = false;
        _error = error.message ?? 'Purchase failed.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _purchaseInFlight = false;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _purchaseInFlight = false;
        });
      }
    }
  }

  Future<void> _handleRestore() async {
    if (_restoreInFlight) {
      return;
    }
    setState(() {
      _restoreInFlight = true;
      _error = null;
    });
    try {
      final customerInfo = await RevenueCatService.restorePurchases();
      _managementUrl = customerInfo.managementURL;
      await _refreshBackendEntitlements();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Purchases restored. Refreshing Pro access...')),
      );
      Navigator.of(context).pop();
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Restore failed.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _restoreInFlight = false;
        });
      }
    }
  }

  Future<void> _refreshBackendEntitlements() async {
    final provider = context.read<NomadeProvider>();
    for (var attempt = 0; attempt < 6; attempt++) {
      await provider.refreshBillingState(notifyListenersNow: false);
      if (provider.hasCloudProAccess) {
        return;
      }
      await Future<void>.delayed(
        Duration(seconds: attempt < 2 ? 1 : 2),
      );
    }
    await provider.refreshBillingState();
  }

  Future<void> _openManagementUrl() async {
    final raw = _managementUrl?.trim() ?? '';
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = context.watch<NomadeProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.workspace_premium_rounded,
                          color: scheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Upgrade to Nomade Pro',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.sourceLabel == null
                                ? 'Unlock more paired devices and paid cloud features.'
                                : 'Triggered from ${widget.sourceLabel}. Unlock more paired devices and paid cloud features.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.primaryContainer,
                        scheme.tertiaryContainer,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pro includes',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _featureLine(
                        context,
                        'More paired devices on Nomade Cloud',
                        scheme.onPrimaryContainer,
                      ),
                      _featureLine(
                        context,
                        'Cloud feature gates unlocked after webhook sync',
                        scheme.onPrimaryContainer,
                      ),
                      _featureLine(
                        context,
                        'Restore purchases on a new device',
                        scheme.onPrimaryContainer,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_offering == null ||
                    _offering!.availablePackages.isEmpty)
                  _buildErrorCard(
                    context,
                    _error ?? 'RevenueCat offering unavailable.',
                    allowRetry: true,
                  )
                else ...[
                  ..._buildPackageCards(context, _offering!),
                  const SizedBox(height: 12),
                  if (_error != null && _error!.trim().isNotEmpty)
                    _buildErrorCard(context, _error!, allowRetry: false),
                  if (provider.deviceLimitReached == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Your current plan has reached its paired-device limit. Upgrade, then reopen agent actions after billing sync completes.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _purchaseInFlight ? null : _handlePurchase,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: _purchaseInFlight
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _selectedPackage == null
                                ? 'Choose a plan'
                                : 'Continue with ${_displayPackageName(_selectedPackage!)}',
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _restoreInFlight ? null : _handleRestore,
                        child: _restoreInFlight
                            ? const Text('Restoring...')
                            : const Text('Restore purchases'),
                      ),
                      const Spacer(),
                      if ((_managementUrl?.trim().isNotEmpty ?? false))
                        TextButton(
                          onPressed: _openManagementUrl,
                          child: const Text('Manage subscription'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPackageCards(BuildContext context, Offering offering) {
    final preferredOrder = <Package?>[
      offering.annual,
      offering.monthly,
    ];
    final seen = <String>{};
    final ordered = <Package>[
      for (final package in preferredOrder)
        if (package != null && seen.add(package.identifier)) package,
      for (final package in offering.availablePackages)
        if (seen.add(package.identifier)) package,
    ];

    return ordered.map((package) {
      final selected = _selectedPackage?.identifier == package.identifier;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final isAnnual = package.packageType == PackageType.annual;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedPackage = package;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.10)
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.8),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _displayPackageName(package),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isAnnual)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Best value',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  package.storeProduct.priceString,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _packageDetail(package),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (_packageSubDetail(package) != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _packageSubDetail(package)!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }).toList(growable: false);
  }

  Widget _buildErrorCard(
    BuildContext context,
    String message, {
    required bool allowRetry,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onErrorContainer,
            ),
          ),
          if (allowRetry) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                unawaited(_loadOffering());
              },
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _featureLine(BuildContext context, String text, Color color) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle_rounded, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _displayPackageName(Package package) {
    switch (package.packageType) {
      case PackageType.annual:
        return 'Annual Pro';
      case PackageType.monthly:
        return 'Monthly Pro';
      default:
        return package.storeProduct.title.trim().isNotEmpty
            ? package.storeProduct.title.trim()
            : package.identifier;
    }
  }

  String _packageDetail(Package package) {
    switch (package.packageType) {
      case PackageType.annual:
        return 'Billed yearly';
      case PackageType.monthly:
        return 'Billed monthly';
      default:
        return package.storeProduct.description;
    }
  }

  String? _packageSubDetail(Package package) {
    if (package.packageType == PackageType.annual) {
      return package.storeProduct.pricePerMonthString == null
          ? null
          : '${package.storeProduct.pricePerMonthString} per month equivalent';
    }
    if (package.packageType == PackageType.monthly) {
      return null;
    }
    final period = package.storeProduct.subscriptionPeriod;
    if (period == null || period.trim().isEmpty) {
      return null;
    }
    return 'Subscription period: $period';
  }
}
