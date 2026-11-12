/// R39 Accounts Workspace V2 — Overview tab, laid out as the approved prototype.
///
/// Four steps, six KPI tiles, then two rows of three cards: Needs Attention,
/// Commercial progress by building, Client collections; Position by building,
/// Where the money stands, Contract snapshot. Server projections supply every
/// figure; percentages and the attention wording are worked out here for
/// display only.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_receivables_inputs.dart';
import '../../domain/accounts_receivables_models.dart';
import '../../domain/accounts_supplier_models.dart';
import '../../domain/v2/accounts_workspace_models.dart';
import '../../domain/v2/claims_list_models.dart';
import '../../domain/v2/commercial_setup_read_models.dart';
import '../../domain/v2/pdc_register_models.dart';
import 'accounts_v2_common.dart';
import 'kit/accounts_v2_kit.dart';
import 'kit/accounts_v2_setup_checks.dart';

/// Where a Needs Attention button leads.
final class AccountsV2OverviewTarget {
  const AccountsV2OverviewTarget(this.tab, {this.invoiceId, this.billId});

  final YorksAccountsWorkspaceV2Tab tab;

  /// Opens this invoice's drawer on the Invoices tab.
  final String? invoiceId;

  /// Opens this bill on the Supplier bills tab.
  final String? billId;
}

/// Maps a workspace step key to the tab it opens.
YorksAccountsWorkspaceV2Tab _tabForStep(String stepKey) => switch (stepKey) {
  'setup' => YorksAccountsWorkspaceV2Tab.contract,
  'progress' => YorksAccountsWorkspaceV2Tab.claims,
  _ => YorksAccountsWorkspaceV2Tab.invoices,
};

class AccountsV2SummaryTab extends StatelessWidget {
  const AccountsV2SummaryTab({
    super.key,
    required this.workspace,
    required this.language,
    required this.onOpenTab,
    required this.onOpenTarget,
    required this.onOpenCell,
    this.setup,
    this.invoices,
    this.cheques,
    this.bills,
    this.claims,
    this.today,
  });

  final YorksAccountsWorkspace workspace;
  final AppLanguage language;
  final ValueChanged<YorksAccountsWorkspaceV2Tab> onOpenTab;
  final ValueChanged<AccountsV2OverviewTarget> onOpenTarget;
  final void Function(String stageKey, String buildingScopeId) onOpenCell;

  /// Each list is null when it is still loading or the person cannot see it;
  /// the Overview then falls back to the server's summary lines.
  final YorksAccountsCommercialSetupRead? setup;
  final List<YorksAccountsClientInvoiceSummary>? invoices;
  final List<YorksAccountsProjectPdc>? cheques;
  final List<YorksAccountsSupplierBill>? bills;
  final List<YorksAccountsClaimSummary>? claims;

  /// Fixed in tests; today otherwise.
  final DateTime? today;

  String _t(String key) => accountsV2Text(language, key);

  /// "#03" for a claim, by its place among the live claims (oldest first), as
  /// the prototype numbers them; the reference when the list isn't loaded.
  String _claimLabel(String? claimId, String? reference) {
    final live = [
      for (final c in (claims ?? const <YorksAccountsClaimSummary>[]).reversed)
        if (c.status != 'cancelled') c,
    ];
    final i = live.indexWhere(
      (c) =>
          c.claimId == claimId ||
          (reference != null && c.reference == reference),
    );
    if (i < 0) return reference ?? '';
    return '#${(i + 1).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final kpis = workspace.kpis;
    final children = <Widget>[
      _Flow(
        steps: workspace.steps,
        language: language,
        setupToFix: setup == null
            ? 0
            : accountsV2SetupChecks(setup!).where((c) => !c.ok).length,
        claimsRecorded: claims?.length,
        claimLabel: _claimLabel,
        onTap: (step) => onOpenTab(_tabForStep(step.key)),
      ),
    ];
    if (kpis != null) {
      children.add(_kpiRow(kpis));
    } else {
      children.add(
        AccountsV2Panel(
          child: AccountsV2Empty(
            icon: workspace.hasBaseline ? 'shield' : 'doc',
            title: workspace.hasBaseline
                ? _t('v2_commercial_hidden')
                : _t('v2_no_baseline_title'),
            body: workspace.hasBaseline ? null : _t('v2_no_baseline_body'),
            action: workspace.hasBaseline
                ? null
                : AccountsV2Button(
                    label: _t('v2_step_setup'),
                    onPressed: () =>
                        onOpenTab(YorksAccountsWorkspaceV2Tab.contract),
                  ),
          ),
        ),
      );
    }
    children.add(
      _ThreeUp(
        children: [
          _AttentionCard(
            items: _attention(),
            language: language,
            onOpen: onOpenTarget,
          ),
          if (kpis != null) _BuildingProgressCard(this),
          if (kpis != null) _CollectionsCard(this),
        ],
      ),
    );
    if (kpis != null) {
      children.add(
        _ThreeUp(
          children: [
            _PositionCard(this),
            _MoneyCard(this),
            _SnapshotCard(this),
          ],
        ),
      );
    }
    return AccountsV2Stack(children: children);
  }

  // ─── KPIs ──────────────────────────────────────────────────────────────────

  Widget _kpiRow(YorksAccountsWorkspaceKpis kpis) {
    final contract = v2Number(kpis.contractValue);
    final invoiced = v2Number(kpis.invoiced);
    final overdue = (invoices ?? const <YorksAccountsClientInvoiceSummary>[])
        .where((i) => i.dueState == YorksAccountsDueState.overdue);
    final overdueAmount = overdue.fold<double>(
      0,
      (a, i) => a + v2Number(i.stillDue),
    );
    final supplier = workspace.supplier;
    return AccountsV2KpiRow(
      children: [
        AccountsV2KpiCard(
          icon: 'doc',
          label: _t('v2_kpi_contract'),
          value: v2Money(contract),
          caption:
              '${_t('v2o_excl_vat')} · '
              '${v2Money(v2Number(kpis.contractInclVat))} '
              '${_t('v2o_with_vat')}',
        ),
        AccountsV2KpiCard(
          icon: 'receipt',
          label: _t('v2_kpi_invoiced'),
          value: v2Money(invoiced),
          caption:
              '${_t('v2o_excl_vat')} · '
              '${v2Pct(contract > 0 ? invoiced / contract * 100 : 0)} '
              '${_t('v2_of_contract')}',
        ),
        AccountsV2KpiCard(
          icon: 'coins',
          tone: AccountsV2Tone.green,
          label: _t('v2_kpi_received'),
          value: v2Money(v2Number(kpis.received)),
          caption: _t('v2o_cleared_incl_vat'),
        ),
        AccountsV2KpiCard(
          icon: 'cheque',
          tone: AccountsV2Tone.vio,
          label: _t('v2o_cheques_in_hand'),
          value: v2Money(v2Number(kpis.chequesInHand)),
          caption: _t('v2o_counted_when_cleared'),
        ),
        AccountsV2KpiCard(
          icon: 'clock',
          tone: AccountsV2Tone.org,
          label: _t('v2o_still_due'),
          value: v2Money(v2Number(kpis.outstanding)),
          valueTone: overdue.isEmpty
              ? AccountsV2ValueTone.plain
              : AccountsV2ValueTone.bad,
          caption: overdue.isEmpty
              ? _t('v2o_nothing_overdue')
              : '${v2Money(overdueAmount)} ${_t('v2o_overdue')}',
        ),
        if (supplier != null)
          AccountsV2KpiCard(
            icon: 'archive',
            tone: supplier.overdueCount > 0
                ? AccountsV2Tone.red
                : AccountsV2Tone.blue,
            label: _t('v2_kpi_supplier_unpaid'),
            value: v2Money(v2Number(supplier.unpaid)),
            valueTone: supplier.overdueCount > 0
                ? AccountsV2ValueTone.bad
                : AccountsV2ValueTone.plain,
            caption:
                '${supplier.overdueCount} ${_t('v2o_overdue')} · '
                '${v2Money(v2Number(supplier.billed))} '
                '${_t('v2o_billed')}',
          ),
      ],
    );
  }

  // ─── Needs Attention ───────────────────────────────────────────────────────

  List<_Attention> _attention() {
    final items = <_Attention>[];
    final now = today ?? DateTime.now();
    String money(Object? v) => v2Money(v2Number(v));
    String days(int n) => n == 1 ? _t('v2o_day') : _t('v2o_days');

    // Contract setup.
    if (setup != null) {
      for (final check in accountsV2SetupChecks(setup!)) {
        if (check.ok) continue;
        items.add(
          _Attention(
            severity: _Severity.bad,
            icon: 'alert',
            title:
                '${_t('v2o_setup_prefix')} '
                '${accountsV2SetupCheckTitle(language, check).toLowerCase()}',
            detail: accountsV2SetupCheckDetail(language, check),
            button: _t('v2_action_open_contract'),
            target: const AccountsV2OverviewTarget(
              YorksAccountsWorkspaceV2Tab.contract,
            ),
          ),
        );
      }
    } else {
      items.addAll(_serverLines(const {'setup_incomplete'}));
    }

    // Cheques.
    if (cheques != null) {
      for (final pdc in cheques!) {
        final target = AccountsV2OverviewTarget(
          YorksAccountsWorkspaceV2Tab.invoices,
          invoiceId: pdc.invoiceId,
        );
        final dd = v2DaysFromToday(pdc.chequeDate.postgresText, today: now);
        final forInvoice =
            '${money(pdc.amount.canonicalText)} ${_t('v2o_for')} '
            '${pdc.invoiceReference}';
        switch (pdc.status) {
          case YorksAccountsPdcStatus.expected:
          case YorksAccountsPdcStatus.received:
            items.add(
              dd <= 0
                  ? _Attention(
                      severity: _Severity.warn,
                      icon: 'cheque',
                      title:
                          '${_t('v2o_deposit_cheque')} ${pdc.chequeNumber} — '
                          '${_t('v2o_it_is_due')}',
                      detail:
                          '$forInvoice · ${_t('v2o_cheque_date')} '
                          '${v2Date(pdc.chequeDate.postgresText)}',
                      button: _t('v2_action_open_invoice'),
                      target: target,
                    )
                  : _Attention(
                      severity: _Severity.pri,
                      icon: 'cheque',
                      title:
                          '${_t('v2o_cheque')} ${pdc.chequeNumber} '
                          '${_t('v2o_in_hand_deposit_on')} '
                          '${v2Date(pdc.chequeDate.postgresText)}',
                      detail:
                          '$forInvoice · $dd ${days(dd)} ${_t('v2o_to_go')} · '
                          '${_t('v2o_counted_received_when_cleared')}',
                      button: _t('v2_action_open_invoice'),
                      target: target,
                    ),
            );
          case YorksAccountsPdcStatus.deposited:
            items.add(
              _Attention(
                severity: _Severity.pri,
                icon: 'cheque',
                title:
                    '${_t('v2o_cheque')} ${pdc.chequeNumber} '
                    '${_t('v2o_deposited_confirm')}',
                detail: forInvoice,
                button: _t('v2_action_open_invoice'),
                target: target,
              ),
            );
          case YorksAccountsPdcStatus.bounced:
            items.add(
              _Attention(
                severity: _Severity.bad,
                icon: 'cheque',
                title:
                    '${_t('v2o_cheque')} ${pdc.chequeNumber} '
                    '${_t('v2o_bounced')}',
                detail: '$forInvoice — ${_t('v2o_follow_up')}',
                button: _t('v2_action_open_invoice'),
                target: target,
              ),
            );
          case YorksAccountsPdcStatus.cleared:
          case YorksAccountsPdcStatus.replaced:
          case YorksAccountsPdcStatus.returned:
          case YorksAccountsPdcStatus.cancelled:
            break;
        }
      }
    } else {
      items.addAll(_serverLines(const {'cheques_in_hand'}));
    }

    // Invoices.
    if (invoices != null) {
      for (final inv in invoices!) {
        if (const {
          YorksAccountsInvoiceStatus.draft,
          YorksAccountsInvoiceStatus.returned,
          YorksAccountsInvoiceStatus.cancelled,
        }.contains(inv.status)) {
          continue;
        }
        final paid = inv.status == YorksAccountsInvoiceStatus.paid;
        final target = AccountsV2OverviewTarget(
          YorksAccountsWorkspaceV2Tab.invoices,
          invoiceId: inv.invoiceId,
        );
        final due = inv.dueDate?.postgresText;
        final dd = v2DaysFromToday(due, today: now);
        if (inv.dueState == YorksAccountsDueState.overdue) {
          items.add(
            _Attention(
              severity: _Severity.bad,
              icon: 'alert',
              title:
                  '${inv.invoiceReference} ${_t('v2o_overdue_by')} ${-dd} '
                  '${days(-dd)}',
              detail:
                  '${_t('v2o_balance')} ${money(inv.stillDue.canonicalText)} · '
                  '${_t('v2o_was_due')} ${v2Date(due)}'
                  '${inv.pdcExposure.isPositive ? ' · ${_t('v2o_cheque_in_hand')}' : ''}',
              button: _t('v2o_record_payment'),
              target: target,
            ),
          );
        } else if (!paid &&
            due != null &&
            dd <= 14 &&
            !inv.pdcExposure.isPositive) {
          items.add(
            _Attention(
              severity: _Severity.warn,
              icon: 'clock',
              title:
                  '${inv.invoiceReference} ${_t('v2o_due_in')} $dd ${days(dd)}',
              detail:
                  '${_t('v2o_balance')} ${money(inv.stillDue.canonicalText)} · '
                  '${_t('v2o_due')} ${v2Date(due)}',
              button: _t('v2_action_open_invoice'),
              target: target,
            ),
          );
        }
        if (inv.certifiedExVat.isZero && !paid) {
          final submitted = inv.submissionDate?.postgresText;
          final ago = -v2DaysFromToday(submitted, today: now);
          items.add(
            _Attention(
              severity: _Severity.pri,
              icon: 'shield',
              title:
                  '${inv.invoiceReference} '
                  '${_t('v2o_waiting_certification')}',
              detail:
                  '${_t('v2o_submitted')} ${v2Date(submitted)} · $ago '
                  '${days(ago)} ${_t('v2o_ago')}',
              button: _t('v2_action_certify'),
              target: target,
            ),
          );
        }
      }
    } else {
      items.addAll(
        _serverLines(const {'invoice_overdue', 'awaiting_certification'}),
      );
    }

    // The claim in progress.
    if (claims != null) {
      final open = claims!.where(
        (c) => c.status == 'draft' || c.status == 'ready_for_accounts',
      );
      final suggested = workspace.attention
          .where((a) => a.kind == 'progress_suggested')
          .fold<int>(
            0,
            (n, a) => n + ((a.params['count'] as num?) ?? 0).toInt(),
          );
      const target = AccountsV2OverviewTarget(
        YorksAccountsWorkspaceV2Tab.claims,
      );
      if (open.isNotEmpty) {
        final claim = open.first;
        final gross = v2Number(claim.grossExVat);
        final checked = claim.status == 'ready_for_accounts';
        final site = suggested > 0
            ? ' · $suggested ${_t('v2o_site_records_waiting')}'
            : '';
        items.add(
          _Attention(
            severity: gross > 0.004 ? _Severity.ok : _Severity.pri,
            icon: 'chart',
            title: gross > 0.004
                ? '${accountsV2ClaimPhrase(language, _claimLabel(claim.claimId, claim.reference))} '
                      '${_t('v2o_has')} ${v2Money(gross)} '
                      '${_t('v2o_ready_to_invoice')}'
                : '${accountsV2ClaimPhrase(language, _claimLabel(claim.claimId, claim.reference))} '
                      '${_t('v2o_is_empty')}',
            detail:
                (checked
                    ? _t('v2o_checked_ready')
                    : _t('v2o_draft_unchecked')) +
                site,
            button: _t('v2_action_open_claim'),
            target: target,
          ),
        );
      } else if (claims!.isNotEmpty || workspace.kpis != null) {
        items.add(
          _Attention(
            severity: _Severity.pri,
            icon: 'chart',
            title: _t('v2_att_no_claim'),
            detail: _t('v2o_start_next_claim'),
            button: _t('v2_action_start_claim'),
            target: target,
          ),
        );
      }
    } else {
      items.addAll(
        _serverLines(const {
          'claim_ready',
          'claim_draft',
          'claim_empty',
          'no_claim',
          'progress_suggested',
        }),
      );
    }

    // Supplier bills.
    if (bills != null) {
      for (final bill in bills!) {
        if (bill.status == YorksAccountsSupplierBillStatus.cancelled) continue;
        final open = bill.outstandingAmount.isPositive;
        final target = AccountsV2OverviewTarget(
          YorksAccountsWorkspaceV2Tab.supplierBills,
          billId: bill.supplierBillId,
        );
        final due = bill.dueDate.postgresText;
        if (open && v2DaysFromToday(due, today: now) < 0) {
          items.add(
            _Attention(
              severity: _Severity.warn,
              icon: 'box',
              title:
                  '${_t('v2o_supplier_bill')} ${bill.supplierInvoiceReference} '
                  '${_t('v2o_overdue')}',
              detail:
                  '${bill.supplierName} · '
                  '${money(bill.outstandingAmount.canonicalText)} '
                  '${_t('v2o_unpaid')} · ${_t('v2o_due')} ${v2Date(due)}',
              button: _t('v2o_open_bill'),
              target: target,
            ),
          );
        }
        if (open && bill.acceptedDelivery == null) {
          items.add(
            _Attention(
              severity: _Severity.warn,
              icon: 'truck',
              title:
                  '${bill.supplierInvoiceReference} '
                  '${_t('v2o_no_delivery_linked')}',
              detail: '${bill.supplierName} · ${_t('v2o_confirm_arrived')}',
              button: _t('v2o_check_bill'),
              target: target,
            ),
          );
        }
      }
    } else {
      items.addAll(_serverLines(const {'supplier_overdue'}));
    }

    items.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return items;
  }

  /// The server's summary lines for the kinds the Overview could not work out
  /// itself (the person cannot see those records, or they are still loading).
  Iterable<_Attention> _serverLines(Set<String> kinds) sync* {
    for (final item in workspace.attention) {
      if (!kinds.contains(item.kind)) continue;
      final count = item.params['count'];
      final title = accountsV2Text(language, 'v2_att_${item.kind}');
      yield _Attention(
        severity: switch (item.severity) {
          'bad' => _Severity.bad,
          'warn' => _Severity.warn,
          'ok' => _Severity.ok,
          _ => _Severity.pri,
        },
        icon: switch (item.kind) {
          'cheques_in_hand' => 'cheque',
          'supplier_overdue' => 'box',
          'setup_incomplete' || 'invoice_overdue' => 'alert',
          'awaiting_certification' => 'shield',
          _ => 'chart',
        },
        title: count is num && count > 0 ? '$title ($count)' : title,
        detail: '',
        button: item.actionKey == null
            ? null
            : accountsV2Text(language, 'v2_action_${item.actionKey}'),
        target: AccountsV2OverviewTarget(switch (item.actionKey) {
          'open_contract' => YorksAccountsWorkspaceV2Tab.contract,
          'open_claim' || 'start_claim' => YorksAccountsWorkspaceV2Tab.claims,
          'open_supplier_bills' => YorksAccountsWorkspaceV2Tab.supplierBills,
          _ => YorksAccountsWorkspaceV2Tab.invoices,
        }),
      );
    }
  }
}

/// The setup check's heading, e.g. "Buildings add up to 100%".
String accountsV2SetupCheckTitle(AppLanguage language, AccountsV2SetupCheck c) {
  String t(String key) => accountsV2Text(language, key);
  return switch (c.kind) {
    AccountsV2SetupCheckKind.contractValue => t('v2o_check_contract'),
    AccountsV2SetupCheckKind.buildings => t('v2o_check_buildings'),
    AccountsV2SetupCheckKind.stages => t('v2o_check_stages'),
    AccountsV2SetupCheckKind.items =>
      '${c.stageName ?? ''}: ${t('v2o_check_items')}',
  };
}

/// The setup check's line beneath, e.g. "Currently 100.00%".
String accountsV2SetupCheckDetail(
  AppLanguage language,
  AccountsV2SetupCheck c,
) {
  String t(String key) => accountsV2Text(language, key);
  String totals(double current) {
    final off = (current - 100).abs();
    final base = '${t('v2o_currently')} ${v2Pct(current, 2)}';
    if (off < 0.005) return base;
    return '$base — ${current < 100 ? t('v2o_missing') : t('v2o_over_by')} '
        '${v2Pct(off, 2)}';
  }

  final shortfall = c.ok
      ? ''
      : ' (${c.shortfallAmount > 0 ? t('v2o_short') : t('v2o_over')} '
            '${t('v2o_by')} ${v2Money(c.shortfallAmount.abs())})';
  return switch (c.kind) {
    AccountsV2SetupCheckKind.contractValue =>
      c.ok ? v2Money(c.current) : t('v2o_enter_contract_value'),
    AccountsV2SetupCheckKind.buildings => totals(c.current),
    AccountsV2SetupCheckKind.stages => totals(c.current),
    AccountsV2SetupCheckKind.items =>
      '${t('v2o_items')} ${v2Fmt(c.current, 3)}% ${t('v2_of_contract')} · '
          '${t('v2o_needed')} ${v2Fmt(c.needed, 3)}% '
          '${t('v2o_per_building')}$shortfall',
  };
}

// ─── Flow steps ──────────────────────────────────────────────────────────────

class _Flow extends StatelessWidget {
  const _Flow({
    required this.steps,
    required this.language,
    required this.setupToFix,
    required this.claimsRecorded,
    required this.claimLabel,
    required this.onTap,
  });

  final List<YorksAccountsWorkspaceStep> steps;
  final AppLanguage language;
  final int setupToFix;
  final int? claimsRecorded;
  final String Function(String? claimId, String? reference) claimLabel;
  final ValueChanged<YorksAccountsWorkspaceStep> onTap;

  String _t(String key) => accountsV2Text(language, key);

  String _detail(YorksAccountsWorkspaceStep step) {
    final d = step.detail;
    switch (step.key) {
      case 'setup':
        if (!step.isDone && setupToFix > 0) {
          return '$setupToFix ${_t('v2o_items_to_complete')}';
        }
        if (d?.contractValue == null) return '';
        return '${v2Money(v2Number(d!.contractValue))} · '
            '${d.buildingCount ?? 0} ${_t('v2_buildings')} · '
            '${d.stageCount ?? 0} ${_t('v2_stages')}';
      case 'progress':
        if (d?.claimReference != null) {
          final gross = d!.claimGross == null
              ? ''
              : ' · ${v2Money(v2Number(d.claimGross))}';
          return '${accountsV2ClaimPhrase(language, claimLabel(null, d.claimReference))} '
              '${_t('v2_in_progress')}$gross';
        }
        return '${claimsRecorded ?? 0} ${_t('v2o_claims_recorded')}';
      case 'invoice':
        final count = d?.issuedCount ?? 0;
        if (count == 0) return _t('v2o_nothing_issued');
        final latest = d?.latestReference;
        return '$count ${_t('v2_issued')}'
            '${latest == null ? '' : ' · ${_t('v2_latest')} $latest'}';
      case 'paid':
        if (d?.received == null || d?.toCome == null) return '';
        return '${v2Money(v2Number(d!.received))} '
            '${_t('v2_received_in')} · '
            '${v2Money(v2Number(d.toCome))} ${_t('v2_to_come')}';
    }
    return '';
  }

  String _title(String key) => switch (key) {
    'setup' => _t('v2_step_setup'),
    'progress' => _t('v2_step_progress'),
    'invoice' => _t('v2_step_invoice'),
    _ => _t('v2_step_paid'),
  };

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    final compact = AccountsV2Breakpoints.isCompact(context);
    final columns = phone ? 1 : (compact ? 2 : 4);
    final tiles = <Widget>[
      for (final (i, step) in steps.indexed)
        _StepTile(
          number: i + 1,
          title: _title(step.key),
          detail: _detail(step),
          done: step.isDone,
          current: step.isCurrent,
          rightRule: columns > 1 && (i + 1) % columns != 0,
          bottomRule: i < steps.length - columns,
          onTap: () => onTap(step),
        ),
    ];
    return AccountsV2Panel(
      child: AccountsV2Grid(columns: columns, gap: 0, children: tiles),
    );
  }
}

class _StepTile extends StatefulWidget {
  const _StepTile({
    required this.number,
    required this.title,
    required this.detail,
    required this.done,
    required this.current,
    required this.rightRule,
    required this.bottomRule,
    required this.onTap,
  });

  final int number;
  final String title;
  final String detail;
  final bool done;
  final bool current;
  final bool rightRule;
  final bool bottomRule;
  final VoidCallback onTap;

  @override
  State<_StepTile> createState() => _StepTileState();
}

class _StepTileState extends State<_StepTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = widget.done
        ? (AccountsV2Colors.ok50, AccountsV2Colors.ok)
        : widget.current
        ? (AccountsV2Colors.pri, Colors.white)
        : (AccountsV2Colors.neu, AccountsV2Colors.neuText);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: _hover ? AccountsV2Colors.rowHover : Colors.transparent,
            border: Border(
              right: widget.rightRule
                  ? const BorderSide(color: AccountsV2Colors.line2)
                  : BorderSide.none,
              bottom: widget.bottomRule
                  ? const BorderSide(color: AccountsV2Colors.line2)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: widget.done
                    ? AccountsV2Icon('check', size: 15, color: fg)
                    : Text(
                        '${widget.number}',
                        style: v2Style(
                          12.5,
                          weight: FontWeight.w700,
                          color: fg,
                          height: 1,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: v2Style(13, weight: FontWeight.w700),
                    ),
                    if (widget.detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Tooltip(
                          message: widget.detail,
                          waitDuration: const Duration(milliseconds: 600),
                          // Two lines before trimming, so figures such as
                          // "AED 1,805,160 in · AED 6,282,777 to come" stay whole.
                          child: Text(
                            widget.detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: v2Style(12, color: AccountsV2Colors.ink2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Three-up rows ───────────────────────────────────────────────────────────

/// `.ov3`: 1.66 : 1 : 1 when wide; the first card on its own row and the other
/// two side by side below 1320px; one column below 760px.
class _ThreeUp extends StatelessWidget {
  const _ThreeUp({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.length == 1) return children.first;
    if (AccountsV2Breakpoints.isNarrow(context)) {
      return AccountsV2Stack(children: children);
    }
    if (!AccountsV2Breakpoints.isWide(context)) {
      return AccountsV2Stack(
        children: [
          children.first,
          AccountsV2Grid(columns: 2, children: children.sublist(1)),
        ],
      );
    }
    return AccountsV2Grid(
      columns: children.length,
      flexes: children.length == 3 ? const [166, 100, 100] : null,
      children: children,
    );
  }
}

// ─── Needs Attention ─────────────────────────────────────────────────────────

enum _Severity { bad, warn, pri, ok }

final class _Attention {
  const _Attention({
    required this.severity,
    required this.icon,
    required this.title,
    required this.detail,
    required this.target,
    this.button,
  });

  final _Severity severity;
  final String icon;
  final String title;
  final String detail;
  final String? button;
  final AccountsV2OverviewTarget target;
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.items,
    required this.language,
    required this.onOpen,
  });

  final List<_Attention> items;
  final AppLanguage language;
  final ValueChanged<AccountsV2OverviewTarget> onOpen;

  @override
  Widget build(BuildContext context) {
    String t(String key) => accountsV2Text(language, key);
    final phone = AccountsV2Breakpoints.isPhone(context);
    final bad = items.any((a) => a.severity == _Severity.bad);
    final count =
        '${items.length} '
        '${items.length == 1 ? t('v2o_item') : t('v2o_items_word')}';
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            icon: 'clip',
            title: t('v2_attention_title'),
            subtitle: t('v2o_attention_sub'),
            actions: [
              AccountsV2Chip(
                count,
                tone: bad ? AccountsV2ChipTone.bad : AccountsV2ChipTone.pri,
              ),
            ],
          ),
          AccountsV2CardBody(
            child: items.isEmpty
                ? AccountsV2Empty(
                    icon: 'check',
                    title: t('v2o_nothing_needs_attention'),
                  )
                : Column(
                    children: [
                      for (final (i, item) in items.indexed)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            border: i == 0
                                ? null
                                : const Border(
                                    top: BorderSide(
                                      color: AccountsV2Colors.line2,
                                    ),
                                  ),
                          ),
                          child: _AttentionRow(
                            item: item,
                            phone: phone,
                            onOpen: () => onOpen(item.target),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.item,
    required this.phone,
    required this.onOpen,
  });

  final _Attention item;
  final bool phone;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tone = switch (item.severity) {
      _Severity.bad => AccountsV2Tone.red,
      _Severity.warn => AccountsV2Tone.org,
      _Severity.ok => AccountsV2Tone.green,
      _Severity.pri => AccountsV2Tone.blue,
    };
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: v2Style(13, weight: FontWeight.w700)),
        if (item.detail.isNotEmpty)
          Text(item.detail, style: v2Style(12, color: AccountsV2Colors.ink2)),
      ],
    );
    final button = item.button == null
        ? null
        : AccountsV2Button(
            label: item.button!,
            size: AccountsV2ButtonSize.small,
            onPressed: onOpen,
          );
    return Row(
      children: [
        AccountsV2IconTile(
          icon: item.icon,
          tone: tone,
          size: 38,
          radius: 10,
          iconSize: 18,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: phone && button != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [text, const SizedBox(height: 8), button],
                )
              : text,
        ),
        if (!phone && button != null) ...[const SizedBox(width: 12), button],
      ],
    );
  }
}

// ─── Commercial progress by building ─────────────────────────────────────────

class _BuildingProgressCard extends StatelessWidget {
  const _BuildingProgressCard(this.tab);

  final AccountsV2SummaryTab tab;

  @override
  Widget build(BuildContext context) {
    String t(String key) => accountsV2Text(tab.language, key);
    final kpis = tab.workspace.kpis!;
    // Buildings in their first-seen order, each summed over its stages.
    final order = <String>[];
    final names = <String, String>{};
    final invoiced = <String, double>{};
    final value = <String, double>{};
    for (final cell in tab.workspace.heatmap) {
      final id = cell.buildingScopeId;
      if (!names.containsKey(id)) {
        order.add(id);
        names[id] = cell.buildingName;
      }
      invoiced[id] = (invoiced[id] ?? 0) + v2Number(cell.invoicedAmount);
      value[id] = (value[id] ?? 0) + v2Number(cell.stageValue);
    }
    final contract = v2Number(kpis.contractValue);
    final total = v2Number(kpis.invoiced);
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            icon: 'chart',
            title: t('v2o_progress_by_building'),
            subtitle: t('v2o_invoiced_so_far'),
          ),
          AccountsV2CardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final id in order)
                  _BuildingBar(
                    name: names[id]!,
                    percent: (value[id] ?? 0) > 0
                        ? (invoiced[id] ?? 0) / value[id]! * 100
                        : 0,
                    tooltip:
                        '${names[id]}: ${v2Money(invoiced[id] ?? 0)} '
                        '${t('v2o_of')} ${v2Money(value[id] ?? 0)}',
                  ),
                AccountsV2KeyValue(
                  label: t('v2o_all_buildings'),
                  value:
                      '${v2Money(total)} · '
                      '${v2Pct(contract > 0 ? total / contract * 100 : 0)}',
                  sum: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildingBar extends StatelessWidget {
  const _BuildingBar({
    required this.name,
    required this.percent,
    required this.tooltip,
  });

  final String name;
  final double percent;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final label = v2Style(
      10.5,
      weight: FontWeight.w700,
      color: AccountsV2Colors.mut,
      height: 1.2,
    );
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 38),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: label,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AccountsV2Bar(
                height: 26,
                radius: 5,
                segments: [(percent / 100, AccountsV2Colors.pri)],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 46,
              child: Text(
                v2Pct(percent),
                textAlign: TextAlign.right,
                style: label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Client collections ──────────────────────────────────────────────────────

class _CollectionsCard extends StatelessWidget {
  const _CollectionsCard(this.tab);

  final AccountsV2SummaryTab tab;

  @override
  Widget build(BuildContext context) {
    String t(String key) => accountsV2Text(tab.language, key);
    final kpis = tab.workspace.kpis!;
    final cash = tab.workspace.cash;
    final invoiced = tab.invoices
        ?.where(
          (i) =>
              i.status != YorksAccountsInvoiceStatus.cancelled &&
              i.status != YorksAccountsInvoiceStatus.draft,
        )
        .fold<double>(0, (a, i) => a + v2Number(i.totalInclVat));
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(icon: 'wallet', title: t('v2o_collections')),
          AccountsV2CardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (invoiced != null)
                  AccountsV2KeyValue(
                    label: t('v2o_invoiced_incl_vat'),
                    value: v2Money(invoiced),
                  ),
                AccountsV2KeyValue(
                  label: t('v2o_received_cleared'),
                  value: v2Money(v2Number(kpis.received)),
                  tone: AccountsV2ValueTone.ok,
                ),
                AccountsV2KeyValue(
                  label: t('v2o_still_due'),
                  value: v2Money(v2Number(kpis.outstanding)),
                  tone: AccountsV2ValueTone.bad,
                ),
                AccountsV2KeyValue(
                  label: t('v2o_cheques_pdc'),
                  value: v2Money(v2Number(kpis.chequesInHand)),
                  tone: AccountsV2ValueTone.vio,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: AccountsV2Note(child: Text(t('v2o_held_cheques'))),
                ),
                if (cash != null) ...[
                  AccountsV2KeyValue(
                    label: t('v2_cash_paid_suppliers'),
                    value: '− ${v2Money(v2Number(cash.paidToSuppliers))}',
                  ),
                  AccountsV2KeyValue(
                    label: t('v2o_net_cash'),
                    value: v2Money(v2Number(cash.net)),
                    sum: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Position by building ────────────────────────────────────────────────────

class _PositionCard extends StatelessWidget {
  const _PositionCard(this.tab);

  final AccountsV2SummaryTab tab;

  @override
  Widget build(BuildContext context) {
    String t(String key) => accountsV2Text(tab.language, key);
    final cells = tab.workspace.heatmap;
    final buildings = <String, String>{};
    final stages = <String, String>{};
    final stageValue = <String, double>{};
    final stageInvoiced = <String, double>{};
    for (final c in cells) {
      buildings.putIfAbsent(c.buildingScopeId, () => c.buildingName);
      stages.putIfAbsent(c.stageKey, () => c.stageLabel ?? c.stageKey);
      stageValue[c.stageKey] =
          (stageValue[c.stageKey] ?? 0) + v2Number(c.stageValue);
      stageInvoiced[c.stageKey] =
          (stageInvoiced[c.stageKey] ?? 0) + v2Number(c.invoicedAmount);
    }
    final contract = v2Number(tab.workspace.kpis?.contractValue);
    YorksAccountsWorkspaceHeatmapCell? cell(String s, String b) {
      for (final c in cells) {
        if (c.stageKey == s && c.buildingScopeId == b) return c;
      }
      return null;
    }

    final head = v2Style(
      11,
      weight: FontWeight.w700,
      color: AccountsV2Colors.mut,
      letterSpacing: .44,
      height: 1.4,
    );
    Widget table(double? width) {
      Widget stageColumn(Widget child) => Expanded(child: child);
      return SizedBox(
        width: width,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 6),
              child: Row(
                children: [
                  stageColumn(
                    Text(t('v2o_billing_stage').toUpperCase(), style: head),
                  ),
                  for (final name in buildings.values)
                    SizedBox(
                      width: 76,
                      child: Text(
                        name.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: head,
                      ),
                    ),
                  SizedBox(
                    width: 112,
                    child: Text(
                      t('v2o_invoiced').toUpperCase(),
                      textAlign: TextAlign.right,
                      style: head,
                    ),
                  ),
                ],
              ),
            ),
            for (final entry in stages.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    stageColumn(
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.value.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: v2Style(
                                11.5,
                                weight: FontWeight.w700,
                                color: AccountsV2Colors.priInk,
                              ),
                            ),
                            Text(
                              '${v2Pct(contract > 0 ? (stageValue[entry.key] ?? 0) / contract * 100 : 0, 0)} · '
                              '${v2Money(stageValue[entry.key] ?? 0)}',
                              style: v2Style(12, color: AccountsV2Colors.mut),
                            ),
                          ],
                        ),
                      ),
                    ),
                    for (final b in buildings.keys)
                      SizedBox(
                        width: 76,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _HeatCell(
                            cell: cell(entry.key, b),
                            onTap: () => tab.onOpenCell(entry.key, b),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 112,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            v2Fmt(stageInvoiced[entry.key] ?? 0),
                            style: v2Style(
                              12.5,
                              weight: FontWeight.w700,
                              tabular: true,
                            ),
                          ),
                          Text(
                            v2Pct(
                              (stageValue[entry.key] ?? 0) > 0
                                  ? (stageInvoiced[entry.key] ?? 0) /
                                        stageValue[entry.key]! *
                                        100
                                  : 0,
                              0,
                            ),
                            style: v2Style(12, color: AccountsV2Colors.mut),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            icon: 'hier',
            title: t('v2o_position_by_building'),
            subtitle: t('v2o_position_sub'),
          ),
          AccountsV2CardBody(
            // Side by side with other cards the table takes the card width;
            // stacked on a narrow window it scrolls sideways when it must.
            child: cells.isEmpty
                ? AccountsV2Empty(icon: 'hier', title: t('v2_heatmap_empty'))
                : AccountsV2Breakpoints.isNarrow(context)
                ? LayoutBuilder(
                    builder: (context, c) {
                      final minimum = buildings.length * 76 + 112 + 150.0;
                      if (c.maxWidth >= minimum) return table(null);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(width: minimum, child: table(null)),
                      );
                    },
                  )
                : table(null),
          ),
        ],
      ),
    );
  }
}

class _HeatCell extends StatefulWidget {
  const _HeatCell({required this.cell, required this.onTap});

  final YorksAccountsWorkspaceHeatmapCell? cell;
  final VoidCallback onTap;

  @override
  State<_HeatCell> createState() => _HeatCellState();
}

class _HeatCellState extends State<_HeatCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final value = v2Number(cell?.stageValue);
    final q = value > 0 ? v2Number(cell?.invoicedAmount) / value * 100 : 0.0;
    final done = q >= 99.99;
    final bg = done
        ? AccountsV2Colors.heatDone
        : q > 0
        ? AccountsV2Colors.pri.withValues(alpha: .08 + q / 100 * .26)
        : AccountsV2Colors.heatEmpty;
    final fg = done
        ? AccountsV2Colors.ok
        : q > 0
        ? AccountsV2Colors.priInk
        : AccountsV2Colors.mut2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
            boxShadow: _hover
                ? const [
                    BoxShadow(color: AccountsV2Colors.pri100, spreadRadius: 2),
                  ]
                : null,
          ),
          child: Text(
            q > 0 ? v2Pct(q, 0) : '—',
            style: v2Style(12, weight: FontWeight.w700, color: fg, height: 1),
          ),
        ),
      ),
    );
  }
}

// ─── Where the money stands ──────────────────────────────────────────────────

class _MoneyCard extends StatelessWidget {
  const _MoneyCard(this.tab);

  final AccountsV2SummaryTab tab;

  @override
  Widget build(BuildContext context) {
    String t(String key) => accountsV2Text(tab.language, key);
    final flow = tab.workspace.moneyFlow;
    final total = v2Number(tab.workspace.kpis?.contractValue);
    final paid = v2Number(flow?.paid);
    final waiting = v2Number(flow?.invoicedWaiting);
    final ready = v2Number(flow?.doneNotInvoiced);
    final remaining = v2Number(flow?.remaining);
    double share(double v) => total > 0 ? v / total : 0;
    Widget legend(Color color, String label, double v) => Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AccountsV2Colors.line2)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: v2Style(12.5, color: AccountsV2Colors.mut),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                v2Money(v),
                style: v2Style(12, weight: FontWeight.w700, tabular: true),
              ),
              Text(
                v2Pct(share(v) * 100),
                style: v2Style(
                  10.5,
                  weight: FontWeight.w500,
                  color: AccountsV2Colors.mut,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            icon: 'spark',
            title: t('v2o_money_title'),
            subtitle: t('v2o_money_sub'),
          ),
          AccountsV2CardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 10),
                  child: AccountsV2Bar(
                    height: 26,
                    radius: 6,
                    segments: [
                      (share(paid), AccountsV2Colors.ok),
                      (share(waiting), AccountsV2Colors.pri),
                      (share(ready), AccountsV2Colors.priLight),
                    ],
                  ),
                ),
                legend(AccountsV2Colors.ok, t('v2_flow_paid'), paid),
                legend(AccountsV2Colors.pri, t('v2o_flow_waiting'), waiting),
                legend(AccountsV2Colors.priLight, t('v2o_flow_ready'), ready),
                legend(
                  AccountsV2Colors.lineS,
                  t('v2_flow_remaining'),
                  remaining,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Contract snapshot ───────────────────────────────────────────────────────

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard(this.tab);

  final AccountsV2SummaryTab tab;

  @override
  Widget build(BuildContext context) {
    String t(String key) => accountsV2Text(tab.language, key);
    final setup = tab.setup;
    final client =
        setup?.clientParty?.name ?? setup?.mainContractorParty?.name ?? '—';
    final stages = setup?.stages ?? const <YorksAccountsSetupReadStage>[];
    final terms = setup?.paymentTermsDays;
    final vat = setup?.vatRatePercent;
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(icon: 'doc', title: t('v2o_snapshot')),
          AccountsV2CardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccountsV2KeyValue(label: t('v2o_client'), value: client),
                AccountsV2KeyValue(
                  label: t('v2o_work_order'),
                  value: setup?.workOrderNumber ?? '—',
                ),
                AccountsV2KeyValue(
                  label: t('v2o_physical_buildings'),
                  value: '${setup?.buildings.length ?? 0}',
                ),
                AccountsV2KeyValue(
                  label: t('v2_stages_title'),
                  value: stages.isEmpty
                      ? '—'
                      : stages
                            .map(
                              (s) => v2Pct(
                                v2Number(s.allocationPercent.canonicalText),
                                0,
                              ),
                            )
                            .join(' / '),
                ),
                AccountsV2KeyValue(
                  label: t('v2o_payment_terms'),
                  value: terms == null
                      ? '—'
                      : '$terms ${t('v2o_days_from_submission')}',
                ),
                AccountsV2KeyValue(
                  label: t('v2o_vat_rate'),
                  value: vat == null
                      ? '—'
                      : v2Pct(v2Number(vat.canonicalText), 0),
                ),
                AccountsV2KeyValue(
                  label: t('v2o_next_invoice'),
                  value: setup?.invoiceSettings?.nextInvoiceNumber ?? '—',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
