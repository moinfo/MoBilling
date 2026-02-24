<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ExpenseResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'sub_expense_category_id' => $this->sub_expense_category_id,
            'sub_category' => $this->when($this->relationLoaded('subCategory') && $this->subCategory, fn () => [
                'id' => $this->subCategory->id,
                'name' => $this->subCategory->name,
                'category' => $this->when($this->subCategory->relationLoaded('category') && $this->subCategory->category, fn () => [
                    'id' => $this->subCategory->category->id,
                    'name' => $this->subCategory->category->name,
                ]),
            ]),
            'description' => $this->description,
            'amount' => $this->amount,
            'expense_date' => $this->expense_date?->format('Y-m-d'),
            'payment_method' => $this->payment_method,
            'control_number' => $this->control_number,
            'reference' => $this->reference,
            'notes' => $this->notes,
            'attachment_url' => $this->attachment_path ? asset('storage/' . $this->attachment_path) : null,
            'created_at' => $this->created_at,
        ];
    }
}
