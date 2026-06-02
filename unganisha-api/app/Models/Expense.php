<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Expense extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'sub_expense_category_id', 'petty_cash_account_id',
        'description', 'amount',
        'expense_date', 'payment_method', 'control_number', 'reference',
        'notes', 'attachment_path',
        'given_by_name', 'received_by_name', 'voucher_attachment_path',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'expense_date' => 'date',
    ];

    public function subCategory()
    {
        return $this->belongsTo(SubExpenseCategory::class, 'sub_expense_category_id');
    }

    public function pettyCashAccount()
    {
        return $this->belongsTo(PettyCashAccount::class, 'petty_cash_account_id');
    }
}
