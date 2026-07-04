<?php

namespace App\Exceptions;

use RuntimeException;

/**
 * Thrown inside the order transaction when a coupon's usage cap is hit by a
 * concurrent order between validation and redemption, forcing a rollback.
 */
class CouponUnavailableException extends RuntimeException
{
}
