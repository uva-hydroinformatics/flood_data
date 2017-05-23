
repo = "http://cran.us.r-project.org"
library(caret)
library(ggfortify)
library(ggplot2)
library(dplyr)
library(rpart)
library(rpart.plot)
library(RSQLite)
library(DBI)
library(randomForest)
library(e1071)
library(class)

classify_knn = function(pca.data, obs_data, point, k){
  neighs = get_nn(pca.data, point, k)
  neigh_data = obs_data[neighs,]
  return(names(which.max(table(neigh_data$fld))))
}

get_nn = function(d, point, k){
  point = d[point, ]
  dists = sort(sqrt(rowSums((t(t(d) - point))^2)))
  close_points = names(dists)[2:k]
  return(close_points)
}

base_dir<- "C:/Users/Jeff/Documents/research/Sadler_3rdPaper/manuscript/"
data_dir<- "C:/Users/Jeff/Google Drive/research/Sadler_3rdPaper_Data/"
fig_dir <- paste(base_dir, "Figures/general/", sep="")
db_filename <- "floodData.sqlite"

con = dbConnect(RSQLite::SQLite(), dbname=paste(data_dir, db_filename, sep=""))

df = dbReadTable(con, 'for_model_geog')

df = df[df$is_dntn == 1,]
df = subset(df, rain_daily_sum>0.1)

colnames(df)

in_col_names = c('rain_daily_sum',
                 'rain_hourly_max',
                 'rain_15_min_max', 
                 'rain_prev_3_days', 
                 'gw_daily_avg', 
                 'tide_daily_avg', 
                 'wind_vel_daily_avg',
                 'tide_r15mx', 
                 'tide_rhrmx',
                 'imp',
                 'twi',
                 'dist_to_wa',
                 'dist_to_ba',
                 'Pipe_Geome',
                 'Horizontal',
                 'Invert_Ele',
                 'Vertical_D',
                 'Year_Insta',
                 'Pipe_Lengt',
                 'Rim_Elevat',
                 'Structure1',
                 'Year_Ins_1',
                 'Year_Insta',
                 'elev_1'
                )
out_col_name = 'flooded'
model_data = df[, c(in_col_names, out_col_name)]
model_data[,out_col_name] = model_data[,out_col_name]>0
model_data[,out_col_name] = factor(model_data[,out_col_name])

col_nums = c("twi", "dist_to_wa", "dist_to_ba", "Horizontal", "Invert_Ele", "Vertical_D", "Pipe_Lengt", "Rim_Elevat", "elev_1")
model_data[col_nums] = sapply(model_data[col_nums], as.numeric)
model_data$Structure1 = as.factor(model_data$Structure1)
model_data$Pipe_Geome = as.factor(model_data$Structure1)
model_data$Pipe_Mater = as.factor(model_data$Structure1)
str(model_data)

boxplot(model_data$rain_daily_sum)
median_fld_dly_rain = quantile(model_data[model_data$flooded == TRUE, 'rain_daily_sum'], .25)
hi_rn_rows = which(model_data$rain_daily_sum>median_fld_dly_rain)
model_data = model_data[-hi_rn_rows,]
boxplot(model_data$rain_daily_sum)

head(model_data[order(-model_data$rain_daily_sum),])

print(summary(model_data$flooded))
sum(as.numeric(model_data$flooded == TRUE))/sum(as.numeric(model_data$flooded == FALSE))

prt = createDataPartition(model_data[, out_col_name], p=0.7)
train_ind = prt$Resample1
test_ind = rownames(model_data[-train_ind,])
print(length(test_ind) + length(train_ind))
# length(rownames(model_data[model_data[train_ind, out_col_name]==TRUE]))
length(test_ind)

train_data = model_data[train_ind, ]
test_data = model_data[test_ind, ]

nfld_train = rownames(train_data[train_data[, out_col_name] == FALSE,])
fld_train = rownames(train_data[train_data[, out_col_name] == TRUE,])
nfld_test = rownames(test_data[test_data[, out_col_name] == FALSE,])
fld_test = rownames(test_data[test_data[, out_col_name] == TRUE,])
down_sample_percent = .006
nfld_train_dwnsmp = sample(nfld_train, down_sample_percent*length(nfld_train))
train_ind = c(fld_train, nfld_train_dwnsmp)

train_in_data = model_data[train_ind, in_col_names]
test_in_data = model_data[test_ind, in_col_names]

tst_out = model_data[test_ind, out_col_name]
trn_out = model_data[train_ind, out_col_name]

train_col_stds = apply(train_in_data, 2, sd)
train_col_means = colMeans(train_in_data)

train_normalized = t((t(train_in_data)-train_col_means)/train_col_stds)
test_normalized = t((t(test_in_data)-train_col_means)/train_col_stds)

pca = prcomp(train_normalized)
pca$x = -pca$x
pca$rotation=-pca$rotation
p = ggplot(pca$x[,c(1,2)], aes(x=PC1, y=PC2, colour=model_data[train_ind, out_col_name], label=rownames(pca$x)))
p + geom_point() + geom_text()
print(pca)
plot(pca)

trn_preprocessed = predict(pca, train_normalized)
tst_preprocessed = predict(pca, test_normalized)
trn_in = trn_preprocessed
tst_in = tst_preprocessed

train_data = cbind(as.data.frame(trn_in), flooded = model_data[train_ind, out_col_name])
fmla = as.formula(paste(out_col_name, "~", paste(colnames(trn_in), collapse="+")))
fmla

kfit = knn(trn_in, tst_in, trn_out, k=5)
table(tst_out, kfit)

svm_fit = svm(fmla, data=train_data)
svm_pred = predict(svm_fit, tst_in)
table(tst_out, svm_pred)

dt_fmla = as.formula(paste(out_col_name, "~", paste(in_col_names, collapse="+")))
dt_train_data = model_data[train_ind, ]
dt_test_data = model_data[test_ind, in_col_names]

colnames(dt_train_data)

fit = rpart(dt_fmla, method='class', data=dt_train_data, minsplit=2)
printcp(fit)

tiff(paste(fig_dir, "Plot2.tif"), width=9, height=6, units='in', res = 300)
rpart.plot(fit, under=TRUE, cex=0.9, extra=1, varlen = 6)
dev.off()
rpart.plot(fit, under=TRUE, cex=0.9, extra=1, varlen = 6)

pfit<- prune(fit, cp=fit$cptable[which.min(fit$cptable[,"xerror"]),"CP"])
rpart.plot(pfit, under=TRUE, cex=0.9, extra=1, varlen = 6)

pred = predict(pfit, dt_train_data[, in_col_names], type = 'class')
table(trn_out, pred)

pred = predict(pfit, dt_test_data, type = 'class')
table(tst_out, pred)

forest = randomForest(dt_fmla, data = dt_train_data, importance = TRUE, type="classification", nodesize=2)

pred = predict(forest, dt_train_data[, in_col_names])
table(trn_out, pred)

pred = predict(forest, dt_test_data)
table(tst_out, pred)
impo = as.data.frame(forest$importance)
impo = impo[order(-impo$MeanDecreaseGini),]
par(las=2)
barplot(impo$MeanDecreaseGini, names.arg=rownames(impo), ylim = c(0, 70))

lo_fit = glm(fmla, family=binomial(link='logit'), data=train_data)
print(lo_fit)

pred = predict(lo_fit, as.data.frame(tst_in), type="response")
table(tst_out, round(pred)>0)

