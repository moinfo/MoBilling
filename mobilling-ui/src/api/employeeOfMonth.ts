import api from './axios';

export interface EotmCycle {
  id: string;
  period_month_key: string;
  voting_opens_on: string;
  voting_closes_on: string;
  prize_amount: number | null;
  status: 'open' | 'closed';
  winner: { id: string; name: string } | null;
  winner_vote_count: number | null;
  winner_commission_id: string | null;
  tallied_at: string | null;
}

export interface EotmResultRow {
  user_id: string;
  name: string;
  votes: number;
}

export interface EotmTurnout {
  voted: number;
  total: number;
  remaining: number;
}

export interface EotmCurrent {
  cycle: EotmCycle;
  is_open_now: boolean;
  has_voted: boolean;
  my_vote: { candidate_id: string; reason: string } | null;
  candidates: { id: string; name: string }[];
  turnout: EotmTurnout;
  /** Withheld (null) while the cycle is still open — only released once it's auto-tallied/closed. */
  results: EotmResultRow[] | null;
}

export interface EotmVoteDetail {
  id: string;
  reason: string;
  created_at: string;
  voter: { id: string; name: string };
  candidate: { id: string; name: string };
}

export const getEotmCurrent = () => api.get<{ data: EotmCurrent | null }>('/employee-of-month/current');

export const castEotmVote = (data: { cycle_id: string; candidate_id: string; reason: string }) =>
  api.post<{ data: unknown }>('/employee-of-month/vote', data);

export const getEotmCycles = () => api.get<{ data: EotmCycle[] }>('/employee-of-month/cycles');

export const getEotmCycleVotes = (cycleId: string) =>
  api.get<{ data: { cycle: EotmCycle; votes: EotmVoteDetail[]; results: EotmResultRow[] } }>(`/employee-of-month/cycles/${cycleId}/votes`);

export const setEotmPrize = (cycleId: string, prize_amount: number) =>
  api.put<{ data: EotmCycle }>(`/employee-of-month/cycles/${cycleId}/prize`, { prize_amount });
