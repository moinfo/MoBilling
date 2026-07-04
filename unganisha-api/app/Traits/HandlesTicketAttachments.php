<?php

namespace App\Traits;

use App\Models\Ticket;
use App\Models\TicketReply;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

trait HandlesTicketAttachments
{
    /** Allowed upload extensions for ticket attachments (WHMCS-style allowlist). */
    protected array $attachmentMimes = ['pdf', 'png', 'jpg', 'jpeg', 'txt', 'zip', 'doc', 'docx', 'xls', 'xlsx'];

    /** Validation rules for the optional `attachments[]` field on a reply/open request. */
    protected function attachmentValidationRules(): array
    {
        $each = 'file|max:5120|mimes:' . implode(',', $this->attachmentMimes);

        return [
            'attachments'   => 'nullable|array|max:5',
            'attachments.*' => $each,
        ];
    }

    /**
     * Persist any uploaded files for a freshly-created reply.
     * Files land under tickets/{ticket_id}/ on the public disk. Orphaned
     * uploads are cleaned up if a DB write fails.
     */
    protected function storeReplyAttachments(Request $request, Ticket $ticket, TicketReply $reply): void
    {
        if (!$request->hasFile('attachments')) {
            return;
        }

        $storedPaths = [];

        try {
            foreach ($request->file('attachments') as $file) {
                if (!$file || !$file->isValid()) {
                    continue;
                }

                $path = $file->store("tickets/{$ticket->id}", 'local');
                $storedPaths[] = $path;

                $reply->attachments()->create([
                    'tenant_id'     => $ticket->tenant_id,
                    'path'          => $path,
                    'original_name' => mb_substr($file->getClientOriginalName(), 0, 255),
                    'mime'          => $file->getClientMimeType(),
                    'size'          => $file->getSize(),
                ]);
            }
        } catch (\Throwable $e) {
            foreach ($storedPaths as $p) {
                try {
                    Storage::disk('local')->delete($p);
                } catch (\Throwable $cleanupError) {
                    Log::error('Failed to clean up orphan ticket attachment', [
                        'path' => $p, 'exception' => $cleanupError,
                    ]);
                }
            }
            throw $e;
        }
    }
}
