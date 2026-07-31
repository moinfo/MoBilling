<?php

namespace App\Http\Controllers;

use App\Services\MosmsService;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;

/**
 * Settings › WhatsApp: link this tenant to their MoSMS account so WhatsApp
 * messages route through MoSMS (no per-tenant Meta setup needed).
 */
class MosmsController extends Controller
{
    use AuthorizesPermissions;

    public function __construct(private MosmsService $mosms) {}

    /** Link status + balances + available WhatsApp templates. */
    public function status(Request $request)
    {
        $tenant = $request->user()->tenant;
        $account = $this->mosms->accountFor($tenant);

        $out = [
            'linked' => (bool) $account?->isLinked(),
            'email'  => $account?->email,
            'mosms_tenant_id'    => $account?->mosms_tenant_id,
            'custom_template_id' => $account?->custom_template_id,
            'balance'   => null,
            'templates' => [],
        ];

        if ($out['linked']) {
            try {
                $out['balance'] = $this->mosms->balance($tenant);
                $out['templates'] = $this->mosms->templates($tenant);
            } catch (\Throwable $e) {
                $out['error'] = $e->getMessage();   // token may have been revoked
            }
        }

        return response()->json(['data' => $out]);
    }

    /** Link an existing MoSMS account (email + password → stored token). */
    public function link(Request $request)
    {
        $this->authorizePermission('settings.reminders');
        $data = $request->validate([
            'email'    => 'required|email',
            'password' => 'required|string',
        ]);

        try {
            $account = $this->mosms->link($request->user()->tenant, $data['email'], $data['password']);
        } catch (\Throwable $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'message' => 'MoSMS account linked — WhatsApp messages will now be sent through MoSMS.',
            'data'    => ['email' => $account->email, 'custom_template_id' => $account->custom_template_id],
        ]);
    }

    /** Create a new MoSMS account for this tenant. */
    public function register(Request $request)
    {
        $this->authorizePermission('settings.reminders');
        $data = $request->validate([
            'org_name' => 'required|string|max:255',
            'name'     => 'required|string|max:255',
            'email'    => 'required|email',
            'phone'    => 'required|string|max:20',
            'password' => 'required|string|min:8',
        ]);

        try {
            $account = $this->mosms->register($request->user()->tenant, $data);
        } catch (\Throwable $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'message' => 'MoSMS account created and linked.',
            'data'    => ['email' => $account->email, 'custom_template_id' => $account->custom_template_id],
        ]);
    }

    /** Unlink (forget the stored token). */
    public function unlink(Request $request)
    {
        $this->authorizePermission('settings.reminders');
        $this->mosms->accountFor($request->user()->tenant)?->delete();

        return response()->json(['message' => 'MoSMS account unlinked.']);
    }

    /** SMS credit packages from MoSMS (for the buy dialog). */
    public function packages(Request $request)
    {
        try {
            return response()->json(['data' => $this->mosms->packages($request->user()->tenant)]);
        } catch (\Throwable $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /** Start a Pesapal checkout on MoSMS — returns the payment page URL. */
    public function purchase(Request $request)
    {
        $this->authorizePermission('settings.reminders');
        $data = $request->validate([
            'sms_quantity' => 'required|integer|min:100|max:10000000',
            'callback_url' => 'nullable|url|max:500',
        ]);

        try {
            $res = $this->mosms->purchaseSms(
                $request->user()->tenant,
                (int) $data['sms_quantity'],
                $data['callback_url'] ?? null,
            );
        } catch (\Throwable $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        if (empty($res['redirect_url'])) {
            return response()->json(['message' => 'MoSMS did not return a payment link — try again shortly.'], 422);
        }

        return response()->json(['data' => $res, 'message' => 'Checkout created — complete payment on Pesapal.']);
    }

    /** Send a test WhatsApp message through MoSMS. */
    public function sendTest(Request $request)
    {
        $this->authorizePermission('settings.reminders');
        $data = $request->validate([
            'to'   => 'required|string|max:20',
            'text' => 'required|string|max:1000',
        ]);

        try {
            $res = $this->mosms->sendText($request->user()->tenant, $data['to'], $data['text']);
        } catch (\Throwable $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['message' => $res['message'] ?? 'Queued.', 'data' => $res]);
    }
}
