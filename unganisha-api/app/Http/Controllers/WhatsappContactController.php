<?php

namespace App\Http\Controllers;

use App\Models\Client;
use App\Models\WhatsappContact;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class WhatsappContactController extends Controller
{
    public function index(Request $request)
    {
        $user = auth()->user();

        $query = WhatsappContact::with([
            'client:id,name', 'assignedUser:id,name', 'campaign:id,name', 'creator:id,name',
        ])->latest();

        // Users only see the contacts they registered, unless granted view_all.
        // Legacy contacts with no recorded creator are treated as shared so
        // they don't disappear for staff after per-user visibility was added.
        if (!$user->hasPermission('whatsapp_contacts.view_all')) {
            $query->where(function ($q) use ($user) {
                $q->where('created_by', $user->id)
                  ->orWhereNull('created_by');
            });
        }

        if ($request->label) {
            $query->where('label', $request->label);
        }
        if ($request->source) {
            $query->where('source', $request->source);
        }
        if ($request->search) {
            $query->where(function ($q) use ($request) {
                $q->where('name', 'like', "%{$request->search}%")
                  ->orWhere('phone', 'like', "%{$request->search}%");
            });
        }

        return response()->json($query->get());
    }

    public function store(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'name'               => 'required|string|max:255',
            'phone'              => [
                'required', 'string', 'max:50',
                Rule::unique('whatsapp_contacts')->where('tenant_id', $tenantId),
            ],
            'label'              => 'required|in:lead,new_customer,new_order,follow_up,pending_payment,paid,order_complete',
            'is_important'       => 'boolean',
            'source'             => 'required|in:whatsapp_ad,instagram,facebook,social_media,direct,referral,other',
            'campaign_id'        => 'nullable|uuid|exists:whatsapp_campaigns,id',
            'notes'              => 'nullable|string',
            'services'           => 'nullable|array',
            'services.*'         => 'string',
            'next_followup_date' => 'nullable|date',
            'assigned_to'        => 'nullable|uuid|exists:users,id',
            'client_id'          => 'nullable|uuid|exists:clients,id',
        ]);

        // Check if phone already belongs to an existing client
        $existingClient = Client::where('tenant_id', $tenantId)
            ->where('phone', $data['phone'])
            ->first(['id', 'name', 'email', 'phone']);

        $contact = WhatsappContact::create($data + ['created_by' => auth()->id()]);

        $response = $contact->load(['client:id,name', 'assignedUser:id,name', 'campaign:id,name', 'creator:id,name']);

        return response()->json([
            'contact'          => $response,
            'existing_client'  => $existingClient, // null if not found, client data if match
        ], 201);
    }

    /**
     * A user may only act on contacts they registered, unless they hold the
     * view_all permission.
     */
    private function authorizeAccess(WhatsappContact $contact): void
    {
        $user = auth()->user();
        // Allow: admins (view_all), the owner, or any legacy/shared contact
        // that has no recorded creator.
        if (!$user->hasPermission('whatsapp_contacts.view_all')
            && !is_null($contact->created_by)
            && $contact->created_by !== $user->id) {
            abort(403, 'You can only manage contacts you registered.');
        }
    }

    public function update(Request $request, WhatsappContact $whatsappContact)
    {
        $this->authorizeAccess($whatsappContact);

        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'name'               => 'sometimes|string|max:255',
            'phone'              => [
                'sometimes', 'string', 'max:50',
                Rule::unique('whatsapp_contacts')->where('tenant_id', $tenantId)->ignore($whatsappContact->id),
            ],
            'label'              => 'sometimes|in:lead,new_customer,new_order,follow_up,pending_payment,paid,order_complete',
            'is_important'       => 'boolean',
            'source'             => 'sometimes|in:whatsapp_ad,instagram,facebook,social_media,direct,referral,other',
            'campaign_id'        => 'nullable|uuid|exists:whatsapp_campaigns,id',
            'notes'              => 'nullable|string',
            'services'           => 'nullable|array',
            'services.*'         => 'string',
            'next_followup_date' => 'nullable|date',
            'assigned_to'        => 'nullable|uuid|exists:users,id',
            'client_id'          => 'nullable|uuid|exists:clients,id',
        ]);

        $whatsappContact->update($data);

        return response()->json($whatsappContact->load(['client:id,name', 'assignedUser:id,name', 'campaign:id,name', 'creator:id,name']));
    }

    public function destroy(WhatsappContact $whatsappContact)
    {
        $this->authorizeAccess($whatsappContact);

        $whatsappContact->delete();
        return response()->json(null, 204);
    }

    // Convert lead to client
    public function convertToClient(Request $request, WhatsappContact $whatsappContact)
    {
        $this->authorizeAccess($whatsappContact);

        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'client_id'    => 'nullable|uuid|exists:clients,id',
            'client_name'  => 'required_without:client_id|string|max:255',
            'client_email' => 'nullable|email|max:255',
            'client_phone' => 'nullable|string|max:50',
        ]);

        if (!empty($data['client_id'])) {
            $clientId = $data['client_id'];
        } else {
            // Use contact phone if client_phone not given, but check it's not already taken
            $phone = $data['client_phone'] ?? $whatsappContact->phone;
            $phoneTaken = Client::where('tenant_id', $tenantId)->where('phone', $phone)->exists();

            $client = Client::create([
                'name'  => $data['client_name'],
                'email' => $data['client_email'] ?? null,
                'phone' => $phoneTaken ? null : $phone,
            ]);
            $clientId = $client->id;
        }

        $whatsappContact->update([
            'client_id' => $clientId,
            'label'     => 'new_customer',
        ]);

        return response()->json($whatsappContact->load(['client:id,name', 'assignedUser:id,name']));
    }

    /**
     * Claim a shared/unowned contact — assign it to the current user so it
     * becomes part of "their" contacts.
     */
    public function claim(WhatsappContact $whatsappContact)
    {
        $user = auth()->user();

        // Non-admins may only claim contacts not already owned by someone else.
        if (!$user->hasPermission('whatsapp_contacts.view_all')
            && !is_null($whatsappContact->created_by)
            && $whatsappContact->created_by !== $user->id) {
            abort(403, 'This contact is already assigned to another user.');
        }

        $whatsappContact->update(['created_by' => $user->id]);

        return response()->json(
            $whatsappContact->load(['client:id,name', 'assignedUser:id,name', 'campaign:id,name', 'creator:id,name'])
        );
    }

    /**
     * Release a contact back to the shared pool — for when a user claimed one
     * by mistake. Owners can release their own; admins (view_all) can release any.
     */
    public function unclaim(WhatsappContact $whatsappContact)
    {
        $user = auth()->user();

        if ($whatsappContact->created_by !== $user->id
            && !$user->hasPermission('whatsapp_contacts.view_all')) {
            abort(403, 'You can only unassign contacts assigned to you.');
        }

        $whatsappContact->update(['created_by' => null]);

        return response()->json(
            $whatsappContact->load(['client:id,name', 'assignedUser:id,name', 'campaign:id,name', 'creator:id,name'])
        );
    }

    /**
     * Claim many shared/unowned contacts for the current user in a single query.
     * Optionally scoped to a set of ids (the ones currently shown); otherwise
     * claims every unowned contact in the tenant. The whereNull guard ensures a
     * user can never take contacts already owned by someone else.
     * Route is admin-gated (whatsapp_contacts.view_all).
     */
    public function claimBulk(Request $request)
    {
        $data = $request->validate([
            'ids'   => 'nullable|array',
            'ids.*' => 'uuid',
        ]);

        $query = WhatsappContact::whereNull('created_by');
        if (!empty($data['ids'])) {
            $query->whereIn('id', $data['ids']);
        }

        $claimed = $query->update(['created_by' => auth()->id()]);

        return response()->json(['claimed' => $claimed]);
    }

    /**
     * Admin: reassign a contact to a specific user (owner = that user).
     * Route is gated by whatsapp_contacts.view_all.
     */
    public function assign(Request $request, WhatsappContact $whatsappContact)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'user_id' => ['required', 'uuid', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
        ]);

        $whatsappContact->update(['created_by' => $data['user_id']]);

        return response()->json(
            $whatsappContact->load(['client:id,name', 'assignedUser:id,name', 'campaign:id,name', 'creator:id,name'])
        );
    }

    public function stats()
    {
        $user    = auth()->user();
        $viewAll = $user->hasPermission('whatsapp_contacts.view_all');
        // Each stat query starts from a base scoped to the user's own contacts
        // unless they can view all.
        $base = fn () => $viewAll
            ? WhatsappContact::query()
            : WhatsappContact::query()->where(function ($q) use ($user) {
                $q->where('created_by', $user->id)->orWhereNull('created_by');
            });

        $total     = $base()->count();
        $byLabel   = $base()->selectRaw('label, COUNT(*) as count')->groupBy('label')->pluck('count', 'label');
        $bySource  = $base()->selectRaw('source, COUNT(*) as count')->groupBy('source')->pluck('count', 'source');
        $converted = $base()->whereNotNull('client_id')->count();

        return response()->json([
            'total'     => $total,
            'converted' => $converted,
            'by_label'  => $byLabel,
            'by_source' => $bySource,
        ]);
    }
}
