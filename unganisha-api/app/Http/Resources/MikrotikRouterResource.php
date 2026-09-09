<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class MikrotikRouterResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'                => $this->id,
            'name'              => $this->name,
            'host'              => $this->host,
            'api_port'          => $this->api_port,
            'username'          => $this->username,
            'use_tls'           => (bool) $this->use_tls,
            'is_active'         => (bool) $this->is_active,
            'last_tested_at'    => $this->last_tested_at,
            'last_test_status'  => $this->last_test_status,
            'last_test_message' => $this->last_test_message,
            'created_at'        => $this->created_at,
        ];
    }
}
