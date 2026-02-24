<x-mail::layout>
{{-- Header --}}
<x-slot:header>
<x-mail::header :url="config('app.url')">
@if(!empty($tenantBranding['logo_url']))
<img src="{{ $tenantBranding['logo_url'] }}" class="logo" alt="{{ $tenantBranding['name'] ?? config('app.name') }}" style="max-height: 48px; max-width: 200px;">
@endif
{{ $tenantBranding['name'] ?? config('app.name') }}
</x-mail::header>
</x-slot:header>

{{-- Body --}}
{!! $slot !!}

{{-- Subcopy --}}
@isset($subcopy)
<x-slot:subcopy>
<x-mail::subcopy>
{!! $subcopy !!}
</x-mail::subcopy>
</x-slot:subcopy>
@endisset

{{-- Footer --}}
<x-slot:footer>
<x-mail::footer>
@if(!empty($tenantBranding['footer_text']))
{{ $tenantBranding['footer_text'] }}
@else
© {{ date('Y') }} {{ $tenantBranding['name'] ?? config('app.name') }}. {{ __('All rights reserved.') }}
@endif
</x-mail::footer>
</x-slot:footer>
</x-mail::layout>
