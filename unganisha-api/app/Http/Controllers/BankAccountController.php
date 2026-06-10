<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreBankAccountRequest;
use App\Http\Resources\BankAccountResource;
use App\Models\BankAccount;
use Illuminate\Http\Request;

class BankAccountController extends Controller
{
    public function index(Request $request)
    {
        $query = BankAccount::query();

        if ($request->filled('search')) {
            $query->where(function ($q) use ($request) {
                $q->where('bank_name', 'like', '%' . $request->search . '%')
                  ->orWhere('account_number', 'like', '%' . $request->search . '%');
            });
        }

        return BankAccountResource::collection(
            $query->orderBy('bank_name')->paginate($request->per_page ?? 50)
        );
    }

    public function store(StoreBankAccountRequest $request)
    {
        $account = BankAccount::create($request->validated());
        return new BankAccountResource($account);
    }

    public function show(BankAccount $bank_account)
    {
        return new BankAccountResource($bank_account);
    }

    public function update(StoreBankAccountRequest $request, BankAccount $bank_account)
    {
        $bank_account->update($request->validated());
        return new BankAccountResource($bank_account);
    }

    public function destroy(BankAccount $bank_account)
    {
        $bank_account->delete();
        return response()->json(['message' => 'Bank account deleted']);
    }
}
