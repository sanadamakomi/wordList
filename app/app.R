# 单词工具
library(RSQLite)
library(DBI)
library(shiny)
library(shinyjs)
library(shinyBS)
library(dplyr)
library(DT)
library(ipa) # 音标
library(phon) # 音标

test_type_vec <- c("IELTS", "TOFEL", "BOTH", "JNLP")
set.seed(seed = 14412)

# 连接数据库
pool <- dbConnect(SQLite(), dbname = "./data.sqlite")
# 检查表格，没有就新建
dbExecute(pool, 'CREATE TABLE IF NOT EXISTS word_table 
          (
            id INTEGER PRIMARY KEY, -- Autoincrement
            edit_time TEXT,
            remove_flag INTEGER,
            en TEXT,
            ipa TEXT,
            zn TEXT,
            example TEXT,
            score REAL,
            test_type TEXT,
            remarks TEXT
          );')

# 结束app时断开数据库连接
onStop(function() {
    dbDisconnect(pool)
})

# 给必填项加星号的css代码
labelMandatory <- function(label) {
    tagList(
        label,
        span("*", class = "mandatory_star")
    )
}
appCSS <- ".mandatory_star { color: red; }"


# 前端
ui <- fluidPage(
    shinyjs::useShinyjs(),
    shinyjs::inlineCSS(appCSS),
    
    # Application title
    headerPanel(title = "", windowTitle = "单词表"),
    
    h3(strong("Word表编辑页面"), style="text-align:center;color:#0000ff;font-size:250%"),
    helpText("自建单词表，供复习和测试", style="text-align:center"),
    br(),
    
    # 输入单词
    fluidRow(
        column(8, align="center", offset = 2,
               textInput('in_word', '搜索word', value ='', placeholder = '输入单词或中文...', width = "50%")
        )
    ),
    br(),
    
    # 单词表按钮
    helpText("单词表，可以追加或编辑，修改完需要刷新", style="text-align:left"),
    fluidRow(
        actionButton("add_button_word", "Add", icon("plus")),
        actionButton("edit_button_word", "Edit", icon("edit")),
        actionButton("refresh_button_word", "Refresh", icon("refresh"))
    ),
    # 单词表表格
    fluidRow(width="100%",
             dataTableOutput("responses_table_word", width = "100%")
    ),
    br(),
    
    # 测验
    fluidRow(
        selectInput('in_initial', '首字母', choices=c("all", letters)),
        textInput('in_remark', '条件，默认当天', value = format(Sys.time(), "%Y-%m-%d")),
        actionButton("have_review", "复习", class = "btn-primary btn-lg"),
        actionButton("have_test", "小测", class = "btn-primary btn-lg")
    )
)

server <- function(input, output, session) {
    # 1-定义实时响应的变量
    # 清洗输入
    input_word_id <- reactive({
        return(gsub("\\s+", "", input$in_word, perl=TRUE))
    })
    
    # word响应表
    responses_df_word <- reactive({
        input$in_word
        input$submit_word
        input$submit_edit_word
        input$refresh_button_word
        # 输入的id可能是英文或中文
        if (input_word_id() != "") {
            in_text <- input_word_id()
        } else {
            in_text <- "错误输入"
        }
        dbGetQuery(
            conn = pool,
            statement =
                paste0("SELECT *
                FROM word_table
                WHERE (en = ?) OR (zn LIKE '%", in_text, "%')"),
            params = c(in_text))
        
    })
    
    # 2-定义按钮开放条件
    observe({
        in_w <- input_word_id()
        match_table_word <- responses_df_word()
        shinyjs::disable("add_button_word")
        shinyjs::disable("edit_button_word")
        if (in_w != "" & nrow(match_table_word) == 0 ) {
            shinyjs::enable("add_button_word")
        }
        if (in_w != "" & nrow(match_table_word) > 0) {
            shinyjs::enable("edit_button_word")
        }
    })
    
    # 3-定义各种弹窗
    #' 功能一：添加单词
    
    # 弹窗：word词条必填区域
    fieldsMandatoryWord <- c("in_word")
    observe({
        mandatoryFilledWord <- 
            vapply(fieldsMandatoryWord,
                   function(x) {
                       !is.null(input[[x]]) && input[[x]] != ""
                   },
                   logical(1))
        # 检查是不是所有值都是真的
        mandatoryFilledWord <- all(mandatoryFilledWord)
        # 如果缺少了某个就不能启用提交
        shinyjs::toggleState(id = "submit_word", condition = mandatoryFilledWord)
    })
    
    #' 3.2 弹窗外观函数
    #' 添加单词弹窗
    entry_form_word <- function(button_id) {
        showModal(
            modalDialog(
                div(id=("entry_form_word"),
                    tags$head(tags$style(".modal-dialog{ width:400px}")),
                    tags$head(tags$style(HTML(".shiny-split-layout > div {overflow: visible}"))),
                    fluidPage(
                        fluidRow(
                            helpText(labelMandatory(""), paste("单词必填")),
                            textInput("in_word", labelMandatory("单词"), value = input_word_id()),
                            
                            textInput("in_word_ipa", "音标", value = ""),
                            textAreaInput("in_word_zn", "中文", value = "", placeholder = "", height = 50, width = "354px"),
                            textAreaInput("in_word_example", "例句", value = "", placeholder = "", height = 200, width = "354px"),
                            splitLayout(
                                cellWidths = c("150px", "150px"),
                                cellArgs = list(style = "vertical-align: top"),
                                selectInput("remove_word", "移除", multiple = FALSE, choices = c("否", "是")),
                                selectInput("in_word_type", "类型", choices = test_type_vec, selectize=TRUE)
                            ),
                            textInput("in_word_remark", "备注", value = ""),
                            helpText(labelMandatory(""), paste("单词必填")),
                            actionButton(button_id, "Submit")
                        ),
                        easyClose = TRUE
                    )
                )
            )
        )
    }
    
    #' 保存提交结果为dataframe
    format_data_word <- reactive({
        if (is.null(input$remove_word)) {
            format_remove <- 0
        } else {
            if (input$remove_word=="否" | input$remove_word== "") {
                format_remove <- 0
            } else {
                format_remove <- 1
            }
        }
        return(data.frame(edit_time = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                          remove_flag = format_remove,
                          en = gsub("'", "''", gsub("\r|\n|\t", " ", input$in_word)),
                          ipa = ifelse(input$in_word_ipa == "", arpa(phonemes(gsub("'", "''", gsub("\r|\n|\t", " ", input$in_word))), to="ipa"), input$in_word_ipa),
                          zn = input$in_word_zn,
                          example = input$in_word_example,
                          score = 0.9,
                          test_type = input$in_word_type,
                          remarks = ""))
    })
    
    # 新增单词
    append_data_word <- function(data){
        dbWriteTable(pool, "word_table", data, append = TRUE)
    }
    
    #' 点击添加单词按钮，出现弹窗
    #' 弹窗id叫entry_form_word
    #' 弹窗里提交按钮id叫submit_word
    observeEvent(input$add_button_word, priority = 20, {
        entry_form_word("submit_word")
    })
    
    observeEvent(input$submit_word, priority = 20, {
        append_data_word(format_data_word())
        shinyjs::reset("entry_form_word")
        removeModal()
        click("refresh_button_word")
    })
    
    # 编辑单词
    observeEvent(input$edit_button_word, priority = 20,{
        edit_df <- responses_df_word()
        showModal(
            if(length(input$responses_table_word_rows_selected) > 1) {
                modalDialog(
                    title = "警告",
                    paste("只能选中一行"), easyClose = TRUE)
            } else if (length(input$responses_table_word_rows_selected) < 1) {
                modalDialog(
                    title = "警告",
                    paste("请先选中要修改的那一行"), easyClose = TRUE)
            }
        )
        
        if(length(input$responses_table_word_rows_selected) == 1) {
            entry_form_word("submit_edit_word")
            updateTextInput(session, "in_word", value = edit_df[input$responses_table_word_rows_selected, "en"])
            updateTextInput(session, "in_word_ipa", value = edit_df[input$responses_table_word_rows_selected, "ipa"])
            updateTextInput(session, "in_word_zn", value = edit_df[input$responses_table_word_rows_selected, "zn"])
            updateTextInput(session, "in_word_example", value = edit_df[input$responses_table_word_rows_selected, "example"])
            updateTextInput(session, "in_word_type", value = edit_df[input$responses_table_word_rows_selected, "test_type"])
            updateTextInput(session, "remove_word", value = ifelse(edit_df[input$responses_table_word_rows_selected, "remove_flag"] == 1, "是", "否"))
            updateTextInput(session, "in_word_remark", value = edit_df[input$responses_table_word_rows_selected, "remarks"])
        }
    })
    
    observeEvent(input$submit_edit_word, priority = 20, {
        edit_df <- responses_df_word()
        row_selection <- edit_df[input$responses_table_word_row_last_clicked, "id"]
        # 转换remove
        if (is.null(input$remove_word)) {
            format_remove <- 0
        } else {
            if (input$remove_word=="否" | input$remove_word== "") {
                format_remove <- 0
            } else {
                format_remove <- 1
            }
        }
        # print(edit_df)
        dbExecute(pool, paste0('UPDATE "word_table" SET "edit_time" = ?, "remove_flag" = ?, "ipa" = ("',
                               input$in_word_ipa, 
                               '"), "zn" = ("', input$in_word_zn, 
                               '"), "example" = ("', input$in_word_example, 
                               '"), "test_type" = ("', input$in_word_type, 
                               '"), "remarks" = ("', input$in_word_remark, 
                               '") WHERE "id" = ("', row_selection, '")'),
                  param = list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                               format_remove)
        )
        removeModal()
        click("refresh_button_word")
    })
    
    # 4-前端表格
    output$responses_table_word <- DT::renderDataTable({
        responses_df_word() %>% 
            select(-id, -score) %>% 
            datatable(class = "display", selection = "single", rownames = FALSE)
    })
    
    # 5-复习
    # 测验响应表
    responses_df_review <- reactive({
        input$in_initial
        input$in_remark
        if (input$in_initial == "all") {
            dbGetQuery(
                conn = pool,
                statement =
                    paste0("SELECT *
                FROM word_table
                WHERE (edit_time LIKE '%", input$in_remark, "%') OR (remarks LIKE '%)", input$in_remark, "%')"))
        } else {
            dbGetQuery(
                conn = pool,
                statement =
                    paste0("SELECT *
                FROM word_table
                WHERE (edit_time LIKE '%", input$in_remark, 
                           "%') OR (remarks LIKE '%)", input$in_remark, 
                           "%') OR (LOWER(en) LIKE '", input$in_initial, "%')"))
        }
    })
    
    # 定义按钮开放条件
    observe({
        edit_df <- responses_df_review()
        shinyjs::disable("have_review")
        shinyjs::disable("have_test")
        if (nrow(edit_df) > 0 ) {
            shinyjs::enable("have_review")
        }
        if (nrow(edit_df) >= 4) {
            shinyjs::enable("have_test")
        }
    })
    
    # 复习弹窗
    entry_form_review <- function(data) {
        showModal(
            modalDialog(
                h2(data[1, "en"]),
                br(),
                paste0("音标：", data[1, "ipa"]),
                h4(),
                bsCollapse(
                    id = "collapseExample",
                    open = NULL,
                    bsCollapsePanel("翻译", 
                                    HTML(paste0(
                                        h4(data[1, "zn"]), 
                                        br(), 
                                        h4("例句："), 
                                        gsub("\n", "<br/>", data[1, "example"]))), 
                                    style = NULL)),
                footer = tagList(
                    modalButton('Close'),
                    actionButton("review_next_word", "下一个")
                ),
                easyClose = TRUE
            ))
    }

    observeEvent(input$have_review, priority = 20, {
        edit_df <- responses_df_review()
        select_row <- sample(1:nrow(edit_df), 1, replace = FALSE, prob=edit_df[, "score"])
        # print(edit_df[select_row,,drop=FALSE])
        entry_form_review(edit_df[select_row,,drop=FALSE])
    })
    
    # 点击下一个
    observeEvent(input$review_next_word, priority = 20, {
        edit_df <- responses_df_review()
        select_row <- sample(1:nrow(edit_df), 1, replace = FALSE, prob=edit_df[, "score"])
        # print(edit_df[select_row,,drop=FALSE])
        entry_form_review(edit_df[select_row,,drop=FALSE])
    })
    
    # 6-考试
    responses_df_test <- eventReactive(input$have_test, {
        edit_df <- responses_df_review()
        select_row <- sample(1:nrow(edit_df), 1)
        unsect_row <- sample(setdiff(1:nrow(edit_df), select_row), 3, replace = FALSE)
        data.frame(
            x = edit_df[c(select_row, unsect_row), "zn"],
            y = c(TRUE, rep(FALSE, 3)),
            z = edit_df[c(select_row, unsect_row), "en"]
        )
    })
    
    # 考试弹窗
    entry_form_quiz <- function(question, answer, branches) {
        showModal(modalDialog(
            h2(question),
            selectInput("quiz_select", 
                         "", 
                         choices = c("", branches), 
                         selected = NULL,
                         multiple = FALSE),
            uiOutput("quiz_answer"),
            footer = tagList(
                modalButton('Close'),
                actionButton("test_next_word", "下一个")
            ),
            easyClose = TRUE
        ))
    }
    
    observeEvent(input$have_test, {
        new_df <- responses_df_test()
        
        quest <- new_df[which(new_df[,"y"]), "z"]
        correct <- new_df[which(new_df[,"y"]), "x"]
        result <- sample(as.character(as.vector(new_df[, "x"])), 4)
        entry_form_quiz(quest,
                        correct,
                        result)
        output$quiz_answer <- renderUI({
            tagList(HTML(
                if (is.null(input$quiz_select) | (input$quiz_select == "")) {
                    "<br />选择答案并提交"
                } else {
                    if (input$quiz_select == correct) {
                        rsp <- "正确"
                        color <- "green"
                        paste0("<br /><ul><li><b><font color=", color, ">", rsp, "</font></b>
             </li></ul>")
                    } else {
                        rsp <- "错误"
                        color <- "red"
                        paste0("<br /><ul><li><b><font color=", color, ">", rsp, "</font></b>
             </li><li>答案: ", correct, "</li></ul>")
                    }
                }
            ))
        })
    })
    
    observeEvent(input$test_next_word, {
        click("have_test")
    })
}

shinyApp(ui = ui, server = server)