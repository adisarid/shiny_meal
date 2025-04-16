library(shiny)
library(shinychat)
library(bslib)
library(promises)

prompt <- readLines("meal_analyzer_prompt.md", warn = F)

ui <- page_sidebar(
  title = "Meal Analysis Dashboard",
  sidebar = sidebar(
    width = 400,
    chat_ui("chat",
            placeholder = "You can ask me about food!")
  ), 
  card(
    layout_sidebar(
      verbatimTextOutput("json_output"),
      sidebar = fileInput("image_upload", "Upload Meal Image", accept = c("image/png", "image/jpeg"))
    )
  )
)

server <- function(input, output, session) {
  chat <- ellmer::chat_openai(system_prompt = prompt, model = "gpt-4o-mini")
  
  observeEvent(input$chat_user_input, {
    stream <- chat$stream_async(input$chat_user_input)
    chat_append("chat", stream)
  })
  
  json_result <- reactiveVal(NULL)
  
  # You can add logic here to handle the uploaded image
  observeEvent(input$image_upload, {
    if (!is.null(input$image_upload)) {
      # Access the file path: input$image_upload$datapath
      # Access the file name: input$image_upload$name
      # Access the file type: input$image_upload$type
      chat_append("chat", 
                  role = "assistant", 
                  "Hey!, I'm analyzing your meal, please wait...")
      # Process and send the image to the chat assistant:
      stream <- chat$chat_async(
        "Analyze this meal and provide the JSON output as instructed.
        Output just the json content, without back ticks. 
        Make sure it is a valid json.
        ",
        ellmer::content_image_file(input$image_upload$datapath))
      
      # This stream is for capturing the json into a reactive
      stream %...>% {
        result <- .
        json_result(jsonlite::parse_json(result))
        
        stream <- chat$stream_async(
          "Provide a human-readable summary of the meal, keep it concise.
          Add total calories, total carbs, total protein.
          Or if there was an error, provide a nicely formatted error message."
        )
        
        chat_append("chat", 
                    stream)
      }
    }
  })
  
  output$json_output <- renderPrint({
    req(json_result())
    json_result()
  })
}

shinyApp(ui, server)