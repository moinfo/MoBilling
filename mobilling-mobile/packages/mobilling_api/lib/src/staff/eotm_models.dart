/// Employee of the Month: shapes follow `EmployeeOfMonthController` and the
/// web's `src/api/employeeOfMonth.ts`.
library;

import '../json.dart';
import 'hr_models.dart' show NamedUser;

class EotmCycle {
  const EotmCycle({
    required this.id,
    required this.periodMonthKey,
    required this.votingOpensOn,
    required this.votingClosesOn,
    required this.prizeAmount,
    required this.status,
    required this.winner,
    required this.winnerVoteCount,
    required this.winnerCommissionId,
    required this.talliedAt,
  });

  final String id;
  final String periodMonthKey;
  final DateTime? votingOpensOn;
  final DateTime? votingClosesOn;
  final double? prizeAmount;
  final String status; // 'open' | 'closed'
  final NamedUser? winner;
  final int? winnerVoteCount;
  final String? winnerCommissionId;
  final DateTime? talliedAt;

  bool get isClosed => status == 'closed';

  factory EotmCycle.fromJson(Map<String, dynamic> json) => EotmCycle(
        id: json.id(),
        periodMonthKey: json.strOr('period_month_key', ''),
        votingOpensOn: json.date('voting_opens_on'),
        votingClosesOn: json.date('voting_closes_on'),
        prizeAmount: json['prize_amount'] == null ? null : readDouble(json['prize_amount']),
        status: json.strOr('status', 'open'),
        winner: json.object('winner') == null ? null : NamedUser.fromJson(json.object('winner')!),
        winnerVoteCount: json['winner_vote_count'] == null ? null : readInt(json['winner_vote_count']),
        winnerCommissionId: json.str('winner_commission_id'),
        talliedAt: json.date('tallied_at'),
      );
}

class EotmResultRow {
  const EotmResultRow({required this.userId, required this.name, required this.votes});

  final String userId;
  final String name;
  final int votes;

  factory EotmResultRow.fromJson(Map<String, dynamic> json) => EotmResultRow(
        userId: json.id('user_id'),
        name: json.strOr('name', '—'),
        votes: json.count('votes'),
      );
}

class EotmTurnout {
  const EotmTurnout({required this.voted, required this.total, required this.remaining});

  final int voted;
  final int total;
  final int remaining;

  factory EotmTurnout.fromJson(Map<String, dynamic> json) => EotmTurnout(
        voted: json.count('voted'),
        total: json.count('total'),
        remaining: json.count('remaining'),
      );
}

class EotmMyVote {
  const EotmMyVote({required this.candidateId, required this.reason});

  final String candidateId;
  final String reason;

  factory EotmMyVote.fromJson(Map<String, dynamic> json) => EotmMyVote(
        candidateId: json.id('candidate_id'),
        reason: json.strOr('reason', ''),
      );
}

class EotmCurrent {
  const EotmCurrent({
    required this.cycle,
    required this.isOpenNow,
    required this.hasVoted,
    required this.myVote,
    required this.candidates,
    required this.turnout,
    required this.results,
  });

  final EotmCycle cycle;
  final bool isOpenNow;
  final bool hasVoted;
  final EotmMyVote? myVote;
  final List<NamedUser> candidates;
  final EotmTurnout turnout;

  /// Withheld by the server (empty) while the cycle is still open — only
  /// meaningful once `cycle.isClosed`. Never use `results.isEmpty` to decide
  /// whether to show it; always gate on `cycle.isClosed`.
  final List<EotmResultRow> results;

  /// Only true while the window is open AND this person hasn't voted yet —
  /// the one condition under which the vote form (not the results list)
  /// should show.
  bool get canVoteNow => isOpenNow && !hasVoted;

  factory EotmCurrent.fromJson(Map<String, dynamic> json) => EotmCurrent(
        cycle: EotmCycle.fromJson(json.object('cycle') ?? const {}),
        isOpenNow: json.flag('is_open_now'),
        hasVoted: json.flag('has_voted'),
        myVote: json.object('my_vote') == null ? null : EotmMyVote.fromJson(json.object('my_vote')!),
        candidates: json.list('candidates', NamedUser.fromJson),
        turnout: EotmTurnout.fromJson(json.object('turnout') ?? const {}),
        results: json.list('results', EotmResultRow.fromJson),
      );
}
