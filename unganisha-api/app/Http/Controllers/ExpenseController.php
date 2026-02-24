<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreExpenseRequest;
use App\Http\Resources\ExpenseResource;
use App\Models\Expense;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class ExpenseController extends Controller
{
    public function index(Request $request)
    {
        $query = Expense::with('subCategory.category');

        if ($request->has('sub_expense_category_id')) {
            $query->where('sub_expense_category_id', $request->sub_expense_category_id);
        }

        if ($request->filled('search')) {
            $query->where('description', 'like', '%' . $request->search . '%');
        }

        return ExpenseResource::collection(
            $query->orderByDesc('expense_date')->paginate($request->per_page ?? 20)
        );
    }

    public function store(StoreExpenseRequest $request)
    {
        $data = $request->safe()->except('attachment');

        if ($request->hasFile('attachment')) {
            $data['attachment_path'] = $request->file('attachment')->store('receipts/expenses', 'public');
        }

        $expense = Expense::create($data);

        return new ExpenseResource($expense->load('subCategory.category'));
    }

    public function show(Expense $expense)
    {
        return new ExpenseResource($expense->load('subCategory.category'));
    }

    public function update(StoreExpenseRequest $request, Expense $expense)
    {
        $data = $request->safe()->except('attachment');

        if ($request->hasFile('attachment')) {
            // Delete old attachment if exists
            if ($expense->attachment_path) {
                Storage::disk('public')->delete($expense->attachment_path);
            }
            $data['attachment_path'] = $request->file('attachment')->store('receipts/expenses', 'public');
        }

        $expense->update($data);

        return new ExpenseResource($expense->load('subCategory.category'));
    }

    public function destroy(Expense $expense)
    {
        if ($expense->attachment_path) {
            Storage::disk('public')->delete($expense->attachment_path);
        }

        $expense->delete();

        return response()->json(['message' => 'Expense deleted']);
    }
}
