module Gateway.AppGateway
    ( AppGateway(..)
    ) where

import Domain.Payment (Payment)
import Gateway.Gateway
import Gateway.MockGateway
import Gateway.StripeGateway

data AppGateway
    = AppMock MockGateway
    | AppStripe StripeGateway

instance Gateway AppGateway where

    authorize gateway payment =
        case gateway of
            AppMock mockGateway ->
                authorize mockGateway payment

            AppStripe stripeGateway ->
                authorize stripeGateway payment

    capture gateway payment =
        case gateway of
            AppMock mockGateway ->
                capture mockGateway payment

            AppStripe stripeGateway ->
                capture stripeGateway payment

    refund gateway payment =
        case gateway of
            AppMock mockGateway ->
                refund mockGateway payment

            AppStripe stripeGateway ->
                refund stripeGateway payment
