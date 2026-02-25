<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreBillCategoryRequest;
use App\Http\Resources\BillCategoryResource;
use App\Models\BillCategory;

class BillCategoryController extends Controller
{

    public function index()
    {
        $categories = BillCategory::whereNull('parent_id')
            ->with(['children' => fn ($q) => $q->orderBy('name')])
            ->orderBy('name')
            ->get();

        return BillCategoryResource::collection($categories);
    }

    public function store(StoreBillCategoryRequest $request)
    {
        $category = BillCategory::create($request->validated());
        $category->load('children');

        return new BillCategoryResource($category);
    }

    public function show(BillCategory $billCategory)
    {
        return new BillCategoryResource($billCategory->load('children'));
    }

    public function update(StoreBillCategoryRequest $request, BillCategory $billCategory)
    {
        $billCategory->update($request->validated());

        return new BillCategoryResource($billCategory->load('children'));
    }

    public function destroy(BillCategory $billCategory)
    {
        // If this is a parent category with subcategories that have bills, block deletion
        if ($billCategory->children()->whereHas('bills')->exists()) {
            return response()->json([
                'message' => 'Cannot delete category with subcategories that have bills. Remove the bills first.',
            ], 422);
        }

        // Soft-delete children if parent is being deleted
        if ($billCategory->children()->exists()) {
            $billCategory->children()->delete();
        }

        $billCategory->delete();

        return response()->json(['message' => 'Category deleted']);
    }
}
