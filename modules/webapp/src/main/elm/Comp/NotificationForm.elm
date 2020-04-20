module Comp.NotificationForm exposing
    ( Model
    , Msg
    , init
    , update
    , view
    )

import Api
import Api.Model.BasicResult exposing (BasicResult)
import Api.Model.EmailSettingsList exposing (EmailSettingsList)
import Api.Model.NotificationSettings exposing (NotificationSettings)
import Api.Model.Tag exposing (Tag)
import Api.Model.TagList exposing (TagList)
import Comp.CalEventInput
import Comp.Dropdown
import Comp.EmailInput
import Comp.IntField
import Data.CalEvent exposing (CalEvent)
import Data.Flags exposing (Flags)
import Data.Validated exposing (Validated(..))
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onCheck, onClick)
import Http
import Util.Http
import Util.Tag
import Util.Update


type alias Model =
    { settings : NotificationSettings
    , connectionModel : Comp.Dropdown.Model String
    , tagInclModel : Comp.Dropdown.Model Tag
    , tagExclModel : Comp.Dropdown.Model Tag
    , recipients : List String
    , recipientsModel : Comp.EmailInput.Model
    , remindDays : Maybe Int
    , remindDaysModel : Comp.IntField.Model
    , enabled : Bool
    , schedule : Validated CalEvent
    , scheduleModel : Comp.CalEventInput.Model
    , formError : Maybe String
    , submitResp : Maybe BasicResult
    }


type Msg
    = Submit
    | TagIncMsg (Comp.Dropdown.Msg Tag)
    | TagExcMsg (Comp.Dropdown.Msg Tag)
    | ConnMsg (Comp.Dropdown.Msg String)
    | ConnResp (Result Http.Error EmailSettingsList)
    | RecipientMsg Comp.EmailInput.Msg
    | GetTagsResp (Result Http.Error TagList)
    | RemindDaysMsg Comp.IntField.Msg
    | ToggleEnabled
    | CalEventMsg Comp.CalEventInput.Msg
    | SetNotificationSettings (Result Http.Error NotificationSettings)
    | SubmitResp (Result Http.Error BasicResult)


initCmd : Flags -> Cmd Msg
initCmd flags =
    Cmd.batch
        [ Api.getMailSettings flags "" ConnResp
        , Api.getTags flags "" GetTagsResp
        , Api.getNotifyDueItems flags SetNotificationSettings
        ]


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        initialSchedule =
            Data.Validated.Unknown Data.CalEvent.everyMonth

        ( sm, sc ) =
            Comp.CalEventInput.init flags Data.CalEvent.everyMonth
    in
    ( { settings = Api.Model.NotificationSettings.empty
      , connectionModel =
            Comp.Dropdown.makeSingle
                { makeOption = \a -> { value = a, text = a }
                , placeholder = "Select connection..."
                }
      , tagInclModel = Util.Tag.makeDropdownModel
      , tagExclModel = Util.Tag.makeDropdownModel
      , recipients = []
      , recipientsModel = Comp.EmailInput.init
      , remindDays = Just 1
      , remindDaysModel = Comp.IntField.init (Just 1) Nothing True "Remind Days"
      , enabled = False
      , schedule = initialSchedule
      , scheduleModel = sm
      , formError = Nothing
      , submitResp = Nothing
      }
    , Cmd.batch
        [ initCmd flags
        , Cmd.map CalEventMsg sc
        ]
    )


makeSettings : Model -> Validated NotificationSettings
makeSettings model =
    let
        prev =
            model.settings

        conn =
            Comp.Dropdown.getSelected model.connectionModel
                |> List.head
                |> Maybe.map Valid
                |> Maybe.withDefault (Invalid [ "Connection missing" ] "")

        recp =
            if List.isEmpty model.recipients then
                Invalid [ "No recipients" ] []

            else
                Valid model.recipients

        rmdays =
            Maybe.map Valid model.remindDays
                |> Maybe.withDefault (Invalid [ "Remind Days is required" ] 0)

        make smtp rec days timer =
            { prev
                | smtpConnection = smtp
                , tagsInclude = Comp.Dropdown.getSelected model.tagInclModel
                , tagsExclude = Comp.Dropdown.getSelected model.tagExclModel
                , recipients = rec
                , remindDays = days
                , enabled = model.enabled
                , schedule = Data.CalEvent.makeEvent timer
            }
    in
    Data.Validated.map4 make
        conn
        recp
        rmdays
        model.schedule


update : Flags -> Msg -> Model -> ( Model, Cmd Msg )
update flags msg model =
    case msg of
        CalEventMsg lmsg ->
            let
                ( cm, cc, cs ) =
                    Comp.CalEventInput.update flags
                        (Data.Validated.value model.schedule)
                        lmsg
                        model.scheduleModel
            in
            ( { model
                | schedule = cs
                , scheduleModel = cm
              }
            , Cmd.map CalEventMsg cc
            )

        RecipientMsg m ->
            let
                ( em, ec, rec ) =
                    Comp.EmailInput.update flags model.recipients m model.recipientsModel
            in
            ( { model | recipients = rec, recipientsModel = em }
            , Cmd.map RecipientMsg ec
            )

        ConnMsg m ->
            let
                ( cm, _ ) =
                    -- dropdown doesn't use cmd!!
                    Comp.Dropdown.update m model.connectionModel
            in
            ( { model | connectionModel = cm }, Cmd.none )

        ConnResp (Ok list) ->
            let
                names =
                    List.map .name list.items

                cm =
                    Comp.Dropdown.makeSingleList
                        { makeOption = \a -> { value = a, text = a }
                        , placeholder = "Select Connection..."
                        , options = names
                        , selected = List.head names
                        }
            in
            ( { model
                | connectionModel = cm
                , formError =
                    if names == [] then
                        Just "No E-Mail connections configured. Goto E-Mail Settings to add one."

                    else
                        Nothing
              }
            , Cmd.none
            )

        ConnResp (Err err) ->
            ( { model | formError = Just (Util.Http.errorToString err) }, Cmd.none )

        TagIncMsg m ->
            let
                ( m2, c2 ) =
                    Comp.Dropdown.update m model.tagInclModel
            in
            ( { model | tagInclModel = m2 }
            , Cmd.map TagIncMsg c2
            )

        TagExcMsg m ->
            let
                ( m2, c2 ) =
                    Comp.Dropdown.update m model.tagExclModel
            in
            ( { model | tagExclModel = m2 }
            , Cmd.map TagExcMsg c2
            )

        GetTagsResp (Ok tags) ->
            let
                tagList =
                    Comp.Dropdown.SetOptions tags.items
            in
            Util.Update.andThen1
                [ update flags (TagIncMsg tagList)
                , update flags (TagExcMsg tagList)
                ]
                model

        GetTagsResp (Err _) ->
            ( model, Cmd.none )

        RemindDaysMsg m ->
            let
                ( pm, val ) =
                    Comp.IntField.update m model.remindDaysModel
            in
            ( { model
                | remindDaysModel = pm
                , remindDays = val
              }
            , Cmd.none
            )

        ToggleEnabled ->
            ( { model | enabled = not model.enabled }, Cmd.none )

        SetNotificationSettings (Ok s) ->
            let
                ( nm, nc ) =
                    Util.Update.andThen1
                        [ update flags (ConnMsg (Comp.Dropdown.SetSelection [ s.smtpConnection ]))
                        , update flags (TagIncMsg (Comp.Dropdown.SetSelection s.tagsInclude))
                        , update flags (TagExcMsg (Comp.Dropdown.SetSelection s.tagsExclude))
                        ]
                        model

                newSchedule =
                    Data.CalEvent.fromEvent s.schedule
                        |> Maybe.withDefault Data.CalEvent.everyMonth

                ( sm, sc ) =
                    Comp.CalEventInput.init flags newSchedule
            in
            ( { nm
                | settings = s
                , recipients = s.recipients
                , remindDays = Just s.remindDays
                , enabled = s.enabled
                , schedule = Data.Validated.Unknown newSchedule
                , scheduleModel = sm
              }
            , Cmd.batch
                [ nc
                , Cmd.map CalEventMsg sc
                ]
            )

        SetNotificationSettings (Err err) ->
            ( { model | formError = Just (Util.Http.errorToString err) }, Cmd.none )

        Submit ->
            case makeSettings model of
                Valid set ->
                    ( { model | formError = Nothing }
                    , Api.submitNotifyDueItems flags set SubmitResp
                    )

                Invalid errs _ ->
                    let
                        errMsg =
                            String.join ", " errs
                    in
                    ( { model | formError = Just errMsg }, Cmd.none )

                Unknown _ ->
                    ( { model | formError = Just "An unknown error occured" }, Cmd.none )

        SubmitResp (Ok res) ->
            ( { model | submitResp = Just res, formError = Nothing }
            , Cmd.none
            )

        SubmitResp (Err err) ->
            ( { model
                | formError = Nothing
                , submitResp = Just (BasicResult False (Util.Http.errorToString err))
              }
            , Cmd.none
            )


view : String -> Model -> Html Msg
view extraClasses model =
    div
        [ classList
            [ ( "ui form", True )
            , ( extraClasses, True )
            , ( "error"
              , model.formError
                    /= Nothing
                    || (Maybe.map .success model.submitResp
                            |> Maybe.map not
                            |> Maybe.withDefault False
                       )
              )
            , ( "success"
              , Maybe.map .success model.submitResp
                    |> Maybe.withDefault False
              )
            ]
        ]
        [ div [ class "inline field" ]
            [ div [ class "ui checkbox" ]
                [ input
                    [ type_ "checkbox"
                    , onCheck (\_ -> ToggleEnabled)
                    , checked model.enabled
                    ]
                    []
                , label [] [ text "Enabled" ]
                ]
            , span [ class "small-info" ]
                [ text "Enable or disable this task."
                ]
            ]
        , div [ class "required field" ]
            [ label [] [ text "Send via" ]
            , Html.map ConnMsg (Comp.Dropdown.view model.connectionModel)
            , span [ class "small-info" ]
                [ text "The SMTP connection to use when sending notification mails."
                ]
            ]
        , div [ class "required field" ]
            [ label []
                [ text "Recipient(s)"
                ]
            , Html.map RecipientMsg
                (Comp.EmailInput.view model.recipients model.recipientsModel)
            , span [ class "small-info" ]
                [ text "One or more mail addresses, confirm each by pressing 'Return'."
                ]
            ]
        , div [ class "field" ]
            [ label [] [ text "Tags Include (and)" ]
            , Html.map TagIncMsg (Comp.Dropdown.view model.tagInclModel)
            , span [ class "small-info" ]
                [ text "Items must have all tags specified here."
                ]
            ]
        , div [ class "field" ]
            [ label [] [ text "Tags Exclude (or)" ]
            , Html.map TagExcMsg (Comp.Dropdown.view model.tagExclModel)
            , span [ class "small-info" ]
                [ text "Items must not have all tags specified here."
                ]
            ]
        , Html.map RemindDaysMsg
            (Comp.IntField.view model.remindDays
                "required field"
                model.remindDaysModel
            )
        , div [ class "required field" ]
            [ label []
                [ text "Schedule"
                , a
                    [ class "right-float"
                    , href "https://github.com/eikek/calev#what-are-calendar-events"
                    , target "_blank"
                    ]
                    [ i [ class "help icon" ] []
                    , text "Click here for help"
                    ]
                ]
            , Html.map CalEventMsg
                (Comp.CalEventInput.view ""
                    (Data.Validated.value model.schedule)
                    model.scheduleModel
                )
            , span [ class "small-info" ]
                [ text "Specify how often and when this task should run. "
                , text "Use English 3-letter weekdays. Either a single value, "
                , text "a list (ex. 1,2,3), a range (ex. 1..3) or a '*' (meaning all) "
                , text "is allowed for each part."
                ]
            ]
        , div [ class "ui divider" ] []
        , div [ class "ui error message" ]
            [ case Maybe.map .message model.submitResp of
                Just txt ->
                    text txt

                Nothing ->
                    Maybe.withDefault "" model.formError
                        |> text
            ]
        , div [ class "ui success message" ]
            [ text "Successfully saved."
            ]
        , button
            [ class "ui primary button"
            , onClick Submit
            ]
            [ text "Submit"
            ]
        ]
