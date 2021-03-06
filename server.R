library(shiny)
library(shinythemes)
library(shiny)
library(readxl)
#library(ICPIHelpers)
library(tidyverse)
library(rpivotTable)
library(tidytext)
library(DT)
library(reshape2)

options(shiny.maxRequestSize=4000*1024^2)

msd_import <- function(msd_txt){
  
  df <- read_delim(msd_txt, 
                   "\t", 
                   escape_double = FALSE,
                   trim_ws = TRUE,
                   col_types = cols(.default = col_character(), 
                                    targets = col_double(),
                                    qtr1 = col_double(),
                                    qtr2 = col_double(),
                                    qtr3 = col_double(),
                                    qtr4 = col_double(),
                                    cumulative = col_double()
                                    ) 
                   )
}

shinyServer(function(input, output) {
  
  #### PARAMETERS ####
  
  row_count <- reactive({input$narrativesdt_rows_selected})
  operatingunit_name <-reactive({narratives()[[row_count(), 1]]}) 
  indicator_name <- reactive({narratives()[[row_count(), 5]]})
  im_name <- reactive({narratives()[[row_count(), 8]]})
  support_name <- reactive({narratives()[[row_count(), 6]]})
  
  narratives_content <- reactive({
          narratives()[[row_count(), 12]]
  })
  
  bing <- get_sentiments("bing")%>%
    filter(word != "positive") %>%
    filter(word != "positives") %>%
    filter(word != "negative") %>%
    filter(word != "negatives") %>%
    filter(word != "patient") %>%
    filter(word != "achievement") %>%
    filter(word != "emergency ward") %>%
    mutate(sentiment = case_when(
      word == "suppression" ~ "positive",
      TRUE ~ sentiment
    ))
  
  #### NARRATIVES IMPORT ####
  
  narratives <- reactive({
    if(is.null(input$import))
    {
      return()
    }
    isolate({
      narrative_path <- input$import
      data <- read_excel(narrative_path$datapath,
                         col_types = "text",
                         skip = 7)
    })
  })
  
  
  output$narrativesdt <- DT::renderDataTable({
    
    DT::datatable(narratives()[,c(1,3,5,6,7,12)], 
                  selection = "single",
                  rownames=FALSE,
                  filter="top",
                  options = list(
                    searchHighlight = TRUE,
                    scroller = TRUE,
                    scrollX = TRUE,
                    scrollY = 700
                  
                  )
    )
  })
  
  #### MSD ####
  
  data <- reactive({
    inFile <- input$import1
    
    if (is.null(inFile))
      return(NULL)
    
    new_msd <- msd_import(inFile$datapath)
    
    new_msd <- pivot_longer(new_msd,
                            targets:cumulative,
                            names_to = "period",
                            values_to = "value")
    
    new_msd <- unite(new_msd, 
                     "period", 
                     c("fiscal_year", "period"),
                     sep = "_", 
                     remove = T)
    
  })
  
  #### PIVOT TABLE & VISUALS ####
  
  output$op <- renderText({
    operatingunit_name()
  })
  
  output$ind <- renderText({
    indicator_name()
  })
  
  output$sup <- renderText({
    support_name()
  })
  
  output$im <- renderText({
    im_name()
  })
  
  output$title <- renderText({
    paste(operatingunit_name(),indicator_name(),support_name(),im_name(), sep = "; ")
  })
  
  output$content <- renderText({
    narratives_content()
  })
  
  observeEvent(input$display,{
    
    
    output$msd_df <- renderRpivotTable({
      
      rpivotTable(data()%>%
                    filter(operatingunit == operatingunit_name())%>%
                    filter(indicator == indicator_name()) %>%
                    filter(mech_name == im_name()) %>%
                    filter(indicatortype == support_name()) %>% 
                    select(-contains("uid")),
                  rows="period", cols=c("operatingunit","psnu","standardizeddisaggregate"),
                  vals = "value", aggregatorName = "Integer Sum"
      )
      
    })
  })
  
  
  ### TEXT ANALYSIS ###
  
  text_prepare <- reactive({
    
    clean_textdf <- narratives() %>%
      unnest_tokens(word, Narrative)%>%
      anti_join(stop_words)
    
  })
  
  sentiment_df <- reactive({
    
    mersentiment <- text_prepare() %>%
      inner_join(bing) %>%
      count(`Operating Unit`, `Indicator Bundle`, sentiment) %>%
      spread(sentiment, n, fill = 0) %>%
      mutate(sentiment = positive - negative)
  })
  
  
  observeEvent(input$display,{
    
    output$sentiment_ous <- renderPlot(
      
      ggplot(sentiment_df(), aes(`Indicator Bundle`, sentiment, fill = `Operating Unit`)) +
        geom_bar(stat = "identity", show.legend = FALSE) +
        theme(axis.text.x = element_text(size = rel(0.5))) +
        facet_wrap(~`Operating Unit`, scales = "free_x")+
        theme_linedraw() +
        theme(axis.title.x = element_blank())
      
    )
  })
  
  observeEvent(input$display,{
    
    output$sentiment_ou <- renderPlot(
      
      ggplot(sentiment_df()%>% filter(`Operating Unit`==operatingunit_name()), aes(`Indicator Bundle`, sentiment, fill = `Operating Unit`)) +
        geom_bar(stat = "identity", show.legend = FALSE) +
        facet_wrap(~`Operating Unit`, scales = "free_x") +
        theme_linedraw()+
        theme(axis.title.x = element_blank())
      
    )
  })
  
  
  observeEvent(input$display,{
    
  output$sentiment_ou_contribution <- renderPlot({
    
      text_prepare() %>% 
        filter(`Operating Unit`==operatingunit_name()) %>%
        inner_join(bing) %>%
        count(`Indicator Bundle`, word, sentiment, sort = TRUE) %>%
        mutate(n = ifelse(sentiment == "negative", -n, n)) %>%
        mutate(word = reorder(word, n)) %>%
        ggplot(aes(word, n, fill = sentiment)) +
        geom_col() +
        coord_flip() +
        labs(y = "Contribution to sentiment")+
        facet_wrap(~`Indicator Bundle`, scales = "free_y") +
      scale_x_discrete(guide=guide_axis(n.dodge=2)) + 
      theme_linedraw() +
      theme(legend.position = "top", axis.title.x = element_blank())
    })
  })
  
  
  observeEvent(input$display,{
    
    output$sentiment_ou_contribution_ind <- renderPlot({

      text_prepare() %>% 
        filter(`Operating Unit`==operatingunit_name()) %>%
        filter(Indicator==indicator_name()) %>%
        inner_join(bing) %>%
        count(`Indicator Bundle`, Indicator, word, sentiment, sort = TRUE) %>%
        mutate(n = ifelse(sentiment == "negative", -n, n)) %>%
        mutate(word = reorder(word, n)) %>%
        ggplot(aes(word, n, fill = sentiment)) +
        geom_col() +
        coord_flip() +
        labs(y = "Contribution to sentiment")+
        facet_wrap(~Indicator, scales = "free_y") +
        scale_x_discrete(guide=guide_axis(n.dodge=2)) + 
        theme_linedraw() +
        theme(legend.position = "none", axis.title.x = element_blank())
    })
  })
  
  
  ### WORD CLOUD ###
  observeEvent(input$display,{
    output$compare_cloud_ou <- renderPlot({
      text_prepare() %>% 
        filter(`Operating Unit`==operatingunit_name()) %>%
        inner_join(bing) %>%
        count(word, sentiment, sort = TRUE) %>%
        acast(word ~ sentiment, value.var = "n", fill = 0) %>%
        comparison.cloud(colors = c("#F8766D", "#00BFC4"),
                         max.words = 100)
    })
  })
  
  observeEvent(input$display,{
    output$compare_cloud_ouind <- renderPlot({
      text_prepare() %>% 
        filter(`Operating Unit`==operatingunit_name()) %>%
        filter(Indicator==indicator_name()) %>%
        inner_join(bing) %>%
        count(word, sentiment, sort = TRUE) %>%
        acast(word ~ sentiment, value.var = "n", fill = 0) %>%
        comparison.cloud(colors = c("#F8766D", "#00BFC4"),
                         max.words = 100)
    })
  })
  
})
