<?php

namespace App\Http\Controllers;

use App\Http\Resources\SystemVerificationFieldDefinitionResource;
use App\Models\SystemVerification;
use App\Models\SystemVerificationFieldDefinition;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Lets a tenant admin add their OWN daily closing figures (beyond the four
 * built-in ones — SystemVerification::AVAILABLE_FIELDS) without a developer
 * touching code. A field's `key` is generated once from its label and never
 * changes afterwards, since SystemVerification.required_fields and
 * SystemVerificationReport.custom_values both reference it by that key.
 */
class SystemVerificationFieldController extends Controller
{
    public function index()
    {
        return SystemVerificationFieldDefinitionResource::collection(
            SystemVerificationFieldDefinition::orderBy('label')->get()
        );
    }

    public function store(Request $request)
    {
        $data = $request->validate(['label' => 'required|string|max:255']);

        $tenantId = auth()->user()->tenant_id;
        $key = $this->uniqueKeyFor($data['label'], $tenantId);

        $field = SystemVerificationFieldDefinition::create([
            'tenant_id' => $tenantId,
            'key' => $key,
            'label' => $data['label'],
        ]);

        return new SystemVerificationFieldDefinitionResource($field);
    }

    public function update(Request $request, SystemVerificationFieldDefinition $system_verification_field)
    {
        $data = $request->validate(['label' => 'required|string|max:255']);
        // The key stays stable on purpose — existing systems' required_fields
        // and historical reports' custom_values already reference it.
        $system_verification_field->update(['label' => $data['label']]);

        return new SystemVerificationFieldDefinitionResource($system_verification_field);
    }

    public function destroy(SystemVerificationFieldDefinition $system_verification_field)
    {
        $inUse = SystemVerification::query()
            ->whereJsonContains('required_fields', $system_verification_field->key)
            ->exists();

        if ($inUse) {
            throw ValidationException::withMessages([
                'label' => ["\"{$system_verification_field->label}\" is still required by at least one system — remove it from that system first."],
            ]);
        }

        $system_verification_field->delete();

        return response()->json(['message' => 'Field removed']);
    }

    private function uniqueKeyFor(string $label, string $tenantId): string
    {
        $base = Str::slug($label, '_') ?: 'field';
        $builtIn = array_keys(SystemVerification::AVAILABLE_FIELDS);

        $key = $base;
        $suffix = 2;
        while (
            in_array($key, $builtIn, true)
            || SystemVerificationFieldDefinition::where('tenant_id', $tenantId)->where('key', $key)->exists()
        ) {
            $key = "{$base}_{$suffix}";
            $suffix++;
        }

        return $key;
    }
}
