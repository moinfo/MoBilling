<?php

namespace App\Http\Controllers;

use App\Models\CannedReply;
use Illuminate\Http\Request;

class CannedReplyController extends Controller
{
    public function index()
    {
        $items = CannedReply::orderBy('title')->get(['id', 'title', 'body', 'created_at', 'updated_at']);

        return response()->json(['data' => $items]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'title' => 'required|string|max:255',
            'body'  => 'required|string|max:20000',
        ]);

        $reply = CannedReply::create([
            'title' => $data['title'],
            'body'  => $data['body'],
        ]);

        return response()->json(['data' => $reply], 201);
    }

    public function update(Request $request, CannedReply $cannedReply)
    {
        $data = $request->validate([
            'title' => 'required|string|max:255',
            'body'  => 'required|string|max:20000',
        ]);

        $cannedReply->update($data);

        return response()->json(['data' => $cannedReply->fresh()]);
    }

    public function destroy(CannedReply $cannedReply)
    {
        $cannedReply->delete();

        return response()->json(['message' => 'Canned reply deleted.']);
    }
}
