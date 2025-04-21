library(shiny)
library(shinychat)
library(bslib)
library(promises)
library(magick)
library(shinyjs)

prompt <- readLines("meal_analyzer_prompt.md", warn = F)

# For mobile devices, this will switch to camera instead of browse
image_upload_script <- "
    document.addEventListener('DOMContentLoaded', function() {
      var input = document.querySelector('input[type=\"file\"]');
      if (input) {
        input.setAttribute('accept', 'image/*');
        input.setAttribute('capture', 'environment');
      }
    });
  "

# Setup the user interface
ui <- page_sidebar(
  title = "Meal Analysis Dashboard",
  sidebar = sidebar(
    width = 450,
    chat_ui("chat", placeholder = "You can ask me about food!")
  ),
  layout_column_wrap(
    width = 1,
    card(
      tags$script(HTML(image_upload_script)),
      fileInput(
        "image_upload",
        "Upload Meal Image",
        accept = c("image/png", "image/jpeg")
      ),
      shinyjs::useShinyjs(),
      uiOutput("preview"),
      shinyjs::hidden(
        input_task_button(
          "confirm_image",
          label = "Analyze!",
          label_busy = "Analyzing...",
          icon = icon("play")
        )
      )
    )
  ),
  card(reactable::reactableOutput("json_output"))
)

server <- function(input, output, session) {
  chat <- ellmer::chat_openai(system_prompt = prompt, model = "gpt-4o-mini")

  # Observer for chat interactions
  observeEvent(input$chat_user_input, {
    stream <- chat$stream_async(input$chat_user_input)
    chat_append("chat", stream)
  })

  # Retains image analysis results (json)
  json_result <- reactiveVal(NULL)

  # Show analyze button
  observeEvent(input$image_upload$datapath, {
    shinyjs::showElement("confirm_image")
  })

  # Image preview
  output$preview <- renderUI({
    req(input$image_upload$datapath)

    base64 <- base64enc::dataURI(
      file = input$image_upload$datapath,
      mime = input$image_upload$type
    )
    tags$img(
      src = base64,
      style = "display: block; margin-left: 0; margin-right: auto; max-height: 250px; max-width: 100%; height: auto;"
    )
  })

  # Logic here to handle the uploaded image
  observeEvent(input$confirm_image, {
    if (!is.null(input$image_upload)) {
      # Access the file path: input$image_upload$datapath
      # Access the file name: input$image_upload$name
      # Access the file type: input$image_upload$type
      chat_append(
        "chat",
        role = "assistant",
        "Hey!, I'm analyzing your meal, please wait..."
      )
      # Process and send the image to the chat assistant:
      stream <- chat$chat_async(
        "Analyze this meal and provide the JSON output as instructed.
        Output just the json content, without back ticks. 
        Make sure it is a valid json.
        ",
        ellmer::content_image_file(input$image_upload$datapath)
      )

      # This stream is for capturing the json into a reactive
      stream %...>%
        {
          result <- .
          json_result(jsonlite::parse_json(result))

          stream <- chat$stream_async(
            "Provide a human-readable summary of the meal, keep it concise.
          Add total calories, total carbs, total protein.
          Or if there was an error, provide a nicely formatted error message."
          )

          chat_append("chat", stream)
        }
    }
  })

  output$json_output <- reactable::renderReactable({
    req(json_result())

    # Validate that there are ingredients in the json
    validate(need(
      "ingredients" %in% names(json_result()),
      message = "Error occurred, unable to parse meal."
    ))

    json_result()$ingredients |>
      dplyr::bind_rows() |>
      tibble::as_tibble() |>
      reactable::reactable()
  })
}

shinyApp(ui, server)
