<?php

namespace App\Notifications;

use App\Models\Document;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

class DocumentSentConfirmation extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public Document $document) {}

    public function via($notifiable): array
    {
        return ['database'];
    }

    public function toArray($notifiable): array
    {
        $type = ucfirst($this->document->type);

        return [
            'type' => 'document_sent',
            'title' => "{$type} Sent",
            'message' => "{$type} {$this->document->document_number} was sent to {$this->document->client->name}.",
            'url' => '/invoices',
        ];
    }
}
