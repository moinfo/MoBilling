<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreExpenseCategoryRequest;
use App\Http\Resources\ExpenseCategoryResource;
use App\Models\ExpenseCategory;
use App\Models\SubExpenseCategory;

class ExpenseCategoryController extends Controller
{
    public function index()
    {
        $categories = ExpenseCategory::with(['subCategories' => fn ($q) => $q->orderBy('name')])
            ->orderBy('name')
            ->get();

        return ExpenseCategoryResource::collection($categories);
    }

    public function store(StoreExpenseCategoryRequest $request)
    {
        $data = $request->validated();

        // If expense_category_id is present, create a sub-category
        if (!empty($data['expense_category_id'])) {
            $sub = SubExpenseCategory::create($data);
            $category = $sub->category->load('subCategories');
        } else {
            $category = ExpenseCategory::create($data);
            $category->load('subCategories');
        }

        return new ExpenseCategoryResource($category);
    }

    public function show(ExpenseCategory $expenseCategory)
    {
        return new ExpenseCategoryResource($expenseCategory->load('subCategories'));
    }

    public function update(StoreExpenseCategoryRequest $request, string $id)
    {
        $data = $request->validated();

        // Try parent category first, then sub-category
        $category = ExpenseCategory::find($id);
        if ($category) {
            $category->update($data);
            return new ExpenseCategoryResource($category->load('subCategories'));
        }

        $sub = SubExpenseCategory::findOrFail($id);
        $sub->update($data);

        return new ExpenseCategoryResource($sub->category->load('subCategories'));
    }

    public function destroy(string $id)
    {
        // Try parent category first
        $category = ExpenseCategory::find($id);
        if ($category) {
            // Block if any sub-category has expenses
            if ($category->subCategories()->whereHas('expenses')->exists()) {
                return response()->json([
                    'message' => 'Cannot delete category with subcategories that have expenses. Remove the expenses first.',
                ], 422);
            }

            $category->subCategories()->delete();
            $category->delete();

            return response()->json(['message' => 'Category deleted']);
        }

        // Try sub-category
        $sub = SubExpenseCategory::findOrFail($id);
        if ($sub->expenses()->exists()) {
            return response()->json([
                'message' => 'Cannot delete subcategory that has expenses. Remove the expenses first.',
            ], 422);
        }

        $sub->delete();

        return response()->json(['message' => 'Subcategory deleted']);
    }
}
